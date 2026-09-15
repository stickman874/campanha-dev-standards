#!/usr/bin/env bash
# DeepSeek V4.1 Flash worker via opencode's no-shell `deepseek-worker` agent (shipped in the project at .opencode/agents/).
#   worker.sh <repo>   task on stdin → worker edits files, never commits; output on stdout, then `--- git status`.
# Exit 0 = done. Exit 3 = "DEEPSEEK_UNAVAILABLE: <why>" (caller falls back to a Sonnet subagent). Exit 2 = bad usage.
set -u
repo=${1:-}; [ -n "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: worker.sh <repo> < task" >&2; exit 2; }
[ -z "$(git -C "$repo" status --porcelain)" ] || { echo "working tree has uncommitted changes: commit or stash first, so the worker's edits can be told apart and undone" >&2; exit 2; }
tmp=$(mktemp -d); pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
cat > "$tmp/task"; [ -s "$tmp/task" ] || { echo "empty task" >&2; exit 2; }
unavailable() {
  echo "DEEPSEEK_UNAVAILABLE: $1"
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=; echo "--- worker output before it stopped"; tail -n 50 "$tmp/out"; fi
  echo "--- git status (reconcile before redoing the task)"; git -C "$repo" status --short; exit 3
}
command -v opencode >/dev/null || unavailable "opencode not installed"
[ -f "$repo/.opencode/agents/deepseek-worker.md" ] || unavailable ".opencode/agents/deepseek-worker.md missing in the project (run copier update)"
export OPENCODE_EXPERIMENTAL_LSP_TOOL=true
LIMIT='error\.error=.*(usage limit|rate limit|quota|insufficient (balance|credit)|\b40[13]\b)'   # opencode retries these silently and never exits
end=$(( $(date +%s) + ${WORKER_TIMEOUT:-600} ))
(cd "$repo" && exec opencode run --agent deepseek-worker --dir "$repo" --auto --print-logs --log-level ERROR "$(cat "$tmp/task")") > "$tmp/out" 2> "$tmp/err" &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(grep -m1 -iE "$LIMIT" "$tmp/err" | sed 's/.*error\.error="//; s/"$//' | cut -c1-200)"
  [ "$(date +%s)" -ge "$end" ] && unavailable "timeout after ${WORKER_TIMEOUT:-600}s"
  sleep 1
done
wait "$pid"; code=$?; pid=
grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(grep -m1 -iE "$LIMIT" "$tmp/err" | cut -c1-200)"
[ "$code" -eq 0 ] || unavailable "opencode exited $code: $(grep -v '^\s*$' "$tmp/err" | tail -1 | cut -c1-200)"
tail -n 200 "$tmp/out"
echo "--- git status"; git -C "$repo" status --short
