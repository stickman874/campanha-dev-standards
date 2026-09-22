#!/usr/bin/env bash
# plugins/core/scripts/claude.sh
# Claude-only backend of opencode.sh (same contract): runs one project Claude agent (.claude/agents/<agent>.md) unattended.
#   claude.sh <repo> <agent> < prompt
# Env: OPENCODE_TIMEOUT (seconds, 600), OPENCODE_EVENTS (save the raw stream-json events here).
# stdout: the agent's final text. stderr: "claude: tools=N cost=C".
# Exit 0 done · 3 "CLAUDE_UNAVAILABLE: <why>" (claude/agent missing, login, rate limit, error result, timeout, crash) · 2 bad usage.
# The model and tools come from the agent file; no Bash, no MCP. Writes are limited per agent below; the rest is denied (dontAsk).
set -u
repo=${1:-}; agent=${2:-}
[ -n "$agent" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: claude.sh <repo> <agent> < prompt" >&2; exit 2; }
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
result() { jq -r 'select(.type=="result") | .result // empty' "$events" 2>/dev/null; }
text() { local r; r=$(result); [ -n "$r" ] && { echo "$r"; return; }; jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$events" 2>/dev/null; }
unavailable() { stop; echo "CLAUDE_UNAVAILABLE: $1"; text; exit 3; }
command -v claude >/dev/null || unavailable "claude not installed (https://claude.com/claude-code), or not on PATH"
[ -f "$repo/.claude/agents/$agent.md" ] || unavailable ".claude/agents/$agent.md missing in the project (run copier update)"
case $agent in
  reviewer) allow=(Read Glob Grep LSP);;
  docs)     allow=(Read Glob Grep LSP 'Edit(docs/**)' 'Write(docs/**)' 'Edit(CHANGELOG.md)' 'Write(CHANGELOG.md)');;
  *)        allow=(Read Glob Grep LSP Edit Write);;
esac
timeout=${OPENCODE_TIMEOUT:-600}; end=$(( $(date +%s) + timeout ))
(cd "$repo" && exec ${SETSID:-} claude -p --agent "$agent" --output-format stream-json --verbose --permission-mode dontAsk --allowedTools "${allow[@]}" --strict-mcp-config --no-session-persistence < "$tmp/prompt") > "$events" 2> "$tmp/err" &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  [ "$(date +%s)" -ge "$end" ] && unavailable "timeout after ${timeout}s"
  sleep 1
done
wait "$pid"; code=$?; pid=
err=$(jq -r 'select(.type=="result" and (.is_error or .subtype!="success")) | "\(.subtype): \(.result // "" | tostring)"' "$events" 2>/dev/null | head -1)
[ -n "$err" ] && unavailable "claude error: ${err:0:200}"
[ "$code" -eq 0 ] || unavailable "claude exited $code: $(grep -v '^[[:space:]]*$' "$tmp/err" | tail -1 | cut -c1-200)"
text
echo "claude: tools=$(jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")' "$events" 2>/dev/null | wc -l) cost=$(jq -r 'select(.type=="result") | .total_cost_usd // 0' "$events" 2>/dev/null)" >&2
