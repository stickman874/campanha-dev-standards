#!/usr/bin/env bash
# plugins/core/scripts/opencode.sh
# Runs one project opencode agent unattended and returns its final text. Shared by worker.sh, review.sh and nightly.sh.
#   opencode.sh <repo> <agent> < prompt
# Env: OPENCODE_MODEL (adds -m provider/model), OPENCODE_TIMEOUT (seconds, 600), OPENCODE_EVENTS (save the raw JSON events here).
# stdout: the agent's final text. stderr: diagnostics, then "opencode: tools=N tokens=T cost=C".
# Exit 0 done · 3 "DEEPSEEK_UNAVAILABLE: <why>" (opencode/agent missing, usage or auth error, error event, timeout, crash) · 2 bad usage.
set -u
repo=${1:-}; agent=${2:-}
[ -n "$agent" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: opencode.sh <repo> <agent> < prompt" >&2; exit 2; }
tmp=$(mktemp -d); pid=
SETSID=$(command -v setsid || true)
stop() {
  [ -n "$pid" ] || return 0
  if [ -n "$SETSID" ]; then kill -- "-$pid" 2>/dev/null; else kill "$pid" 2>/dev/null; fi
  for i in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if [ -n "$SETSID" ]; then kill -9 -- "-$pid" 2>/dev/null; else kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null; pid=
}
trap 'stop; rm -rf "$tmp"' EXIT
cat > "$tmp/prompt"; [ -s "$tmp/prompt" ] || { echo "empty prompt" >&2; exit 2; }
events=${OPENCODE_EVENTS:-$tmp/events}; : > "$events"
text() { jq -r 'select(.type=="text") | .part.text' "$events" 2>/dev/null; }
reason() { grep -m1 -iE "$LIMIT" "$1" | sed 's/.*error\.error="//; s/"$//' | cut -c1-200; }
unavailable() {
  stop
  echo "DEEPSEEK_UNAVAILABLE: $1"; text; exit 3
}
command -v opencode >/dev/null || unavailable "opencode not installed (curl -fsSL https://opencode.ai/install | bash; opencode auth login)"
[ -f "$repo/.opencode/agents/$agent.md" ] || unavailable ".opencode/agents/$agent.md missing in the project (run copier update)"
LIMIT='usage limit|rate limit|quota|insufficient (balance|credit)|FreeUsageLimit|\b40[13]\b|unauthorized|not logged in'   # opencode retries these silently and never exits
model=(); [ -n "${OPENCODE_MODEL:-}" ] && model=(-m "$OPENCODE_MODEL")
export OPENCODE_EXPERIMENTAL_LSP_TOOL=true
timeout=${OPENCODE_TIMEOUT:-600}; end=$(( $(date +%s) + timeout ))
(cd "$repo" && exec ${SETSID:-} opencode run --format json --agent "$agent" --dir "$repo" --auto ${model[@]+"${model[@]}"} --print-logs --log-level ERROR -f "$tmp/prompt" "see attached file for the task") > "$events" 2> "$tmp/err" &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(reason "$tmp/err")"
  [ "$(date +%s)" -ge "$end" ] && unavailable "timeout after ${timeout}s"
  sleep 1
done
wait "$pid"; code=$?; pid=
grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(reason "$tmp/err")"
err=$(jq -r 'select(.type=="error") | (.error.message // .error // .) | tostring' "$events" 2>/dev/null | head -1)
[ -n "$err" ] && unavailable "opencode error: ${err:0:200}"
[ "$code" -eq 0 ] || unavailable "opencode exited $code: $(grep -v '^[[:space:]]*$' "$tmp/err" | tail -1 | cut -c1-200)"
text
echo "opencode: tools=$(jq -c 'select(.type=="tool_use")' "$events" 2>/dev/null | wc -l) tokens=$(jq -s '[.[] | select(.type=="step_finish") | .part.tokens.total] | add // 0' "$events") cost=$(jq -s '[.[] | select(.type=="step_finish") | .part.cost] | add // 0' "$events")" >&2
