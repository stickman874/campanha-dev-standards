#!/usr/bin/env bash
# DeepSeek V4.1 Flash via opencode, driven by a script so no model sits between Claude and the worker.
#   deepseek.sh run    <repo>          task on stdin  -> no-shell worker edits files, never commits
#   deepseek.sh review <repo> [base]   focus on stdin -> read-only reviewer; diff <base>...HEAD attached if base given
# Exit 0 = done (output on stdout). Exit 3 = "DEEPSEEK_UNAVAILABLE: <why>" (caller falls back). Exit 2 = bad usage.
set -u
mode=${1:-}; repo=${2:-}; base=${3:-}
usage() { echo "usage: deepseek.sh run|review <repo> [base]" >&2; exit 2; }
unavailable() { echo "DEEPSEEK_UNAVAILABLE: $1"; exit 3; }
case $mode in run) agent=deepseek-worker;; review) agent=deepseek-reviewer;; *) usage;; esac
[ -n "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || usage

command -v opencode >/dev/null || unavailable "opencode not installed"
oc=${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}
{ [ -f "$oc/plugins/core-guard.js" ] && [ -f "$oc/agents/$agent.md" ]; } || unavailable "core guard or opencode $agent agent not installed (rerun install.sh)"

pid=; tmp=$(mktemp -d)
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
cat > "$tmp/task.md"   # read from stdin: never expanded by a shell
[ -s "$tmp/task.md" ] || usage

files=()
if [ "$mode" = review ] && [ -n "$base" ]; then
  git -C "$repo" diff "$base...HEAD" > "$tmp/diff.patch" 2>/dev/null || { echo "cannot diff $base...HEAD" >&2; exit 2; }
  [ -s "$tmp/diff.patch" ] || { echo "Verdict: approve"; echo "Findings: none (empty diff $base...HEAD)"; exit 0; }
  files=(-f "$tmp/diff.patch")
fi

# -f takes a list and would swallow a message placed after it, so attachments go last.
(cd "$repo" && exec opencode run --agent "$agent" --dir "$repo" --auto --print-logs --log-level ERROR \
  "$(cat "$tmp/task.md")" ${files[@]+"${files[@]}"}) > "$tmp/out" 2> "$tmp/err" &
pid=$!

# opencode retries a usage/rate limit silently and never exits: watch its error log and give up at the first hit.
LIMIT='usage limit|rate limit|quota|insufficient (balance|credit)|\b40[13]\b'
reason() { grep -m1 -iE "$LIMIT" "$tmp/err" | sed 's/.*error\.error="//; s/"$//' | cut -c1-200; }
end=$(( $(date +%s) + ${DEEPSEEK_TIMEOUT:-580} ))
while kill -0 "$pid" 2>/dev/null; do
  grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(reason)"
  [ "$(date +%s)" -ge "$end" ] && unavailable "timeout after ${DEEPSEEK_TIMEOUT:-580}s"
  sleep 1
done
wait "$pid"; code=$?; pid=
grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(reason)"
[ "$code" -eq 0 ] || unavailable "opencode exited $code: $(grep -v '^\s*$' "$tmp/err" | tail -1 | cut -c1-200)"

tail -n 200 "$tmp/out"
[ "$mode" = run ] && { echo "--- git status"; git -C "$repo" status --short; }
exit 0
