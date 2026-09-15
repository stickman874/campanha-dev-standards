#!/usr/bin/env bash
# DeepSeek worker through the project's no-shell `worker` opencode agent (.opencode/agents/worker.md).
#   worker.sh <repo> < task     the worker edits files and never commits.
# stdout: its report, "--- git status", and "--- claimed but unchanged" (paths under Files: that git does not see).
# Exit 0 done · 3 DEEPSEEK_UNAVAILABLE (caller falls back to a Sonnet subagent) · 4 wrote nothing (≥3 tool calls, no change) · 2 bad usage.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${1:-}; git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: worker.sh <repo> < task" >&2; exit 2; }
[ -z "$(git -C "$repo" status --porcelain)" ] || { echo "working tree has uncommitted changes: commit or stash first, so the worker's edits can be told apart and undone" >&2; exit 2; }
events=$(mktemp); trap 'rm -f "$events"' EXIT
out=$(OPENCODE_EVENTS=$events OPENCODE_TIMEOUT=${WORKER_TIMEOUT:-600} bash "$here/opencode.sh" "$repo" worker); code=$?
echo "$out"
changed=$(git -C "$repo" status --porcelain)
echo "--- git status"; echo "$changed"
[ "$code" -eq 0 ] || exit "$code"
tools=$(jq -c 'select(.type=="tool_use")' "$events" 2>/dev/null | wc -l)
[ -z "$changed" ] && [ "$tools" -ge 3 ] && { echo "worker: wrote nothing ($tools tool calls, no file changed)" >&2; exit 4; }
# ponytail: claims are the "- path — why" lines under Files:; anything git did not see is listed and the caller decides
claimed=$(printf '%s\n' "$out" | sed -n '/^Files:/,/^[A-Z][a-zA-Z]*:/p' | sed -n 's/^- \([^ ]*\).*/\1/p' | sort -u)
paths=$(printf '%s\n' "$changed" | sed 's/^...//; s/.* -> //')
missing=$(for f in $claimed; do printf '%s\n' "$paths" | grep -qxF -- "$f" || echo "$f"; done)
[ -n "$missing" ] && { echo "--- claimed but unchanged"; echo "$missing"; }
exit 0
