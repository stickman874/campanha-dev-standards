#!/usr/bin/env bash
# DeepSeek V4.1 Flash via opencode, driven by a script so no model sits between Claude and the worker.
#   deepseek.sh run    <repo>          task on stdin  -> no-shell worker edits files, never commits
#   deepseek.sh review <repo> [base]   focus on stdin -> read-only reviewer; diff <base>...HEAD attached if base given
# Exit 0 = done (output on stdout). Exit 3 = "DEEPSEEK_UNAVAILABLE: <why>" (caller falls back). Exit 2 = bad usage.
set -u
mode=${1:-}; repo=${2:-}; base=${3:-}
usage() { echo "usage: deepseek.sh run|review <repo> [base]" >&2; exit 2; }
unavailable() {
  echo "DEEPSEEK_UNAVAILABLE: $1"
  if [ -n "${launched:-}" ]; then   # it may have edited files before stopping: hand back what we know
    [ -n "$pid" ] && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=; }
    echo "--- worker output before it stopped"; tail -n 50 "$tmp/out"
    [ "$mode" = run ] && { echo "--- git status (it may have changed these: reconcile before redoing the task)"; git -C "$repo" status --short; }
  fi
  exit 3
}
case $mode in run) agent=deepseek-worker;; review) agent=deepseek-reviewer;; *) usage;; esac
[ -n "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || usage
# a clean tree means every change afterwards is the worker's, so a failed run can be undone without touching the user's edits
if [ "$mode" = run ] && [ -n "$(git -C "$repo" status --porcelain)" ]; then
  echo "working tree has uncommitted changes: commit or stash them first, so the worker's edits can be told apart and safely undone" >&2; exit 2
fi

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

# opencode retries a usage/rate limit silently and never exits: watch its error log and give up at the first hit.
LIMIT='usage limit|rate limit|quota|insufficient (balance|credit)|\b40[13]\b'
reason() { grep -m1 -iE "$LIMIT" "$tmp/err" | sed 's/.*error\.error="//; s/"$//' | cut -c1-200; }
end=$(( $(date +%s) + ${DEEPSEEK_TIMEOUT:-580} ))   # one budget for every worker round and test run
launch() {   # $1 = message
  # -f takes a list and would swallow a message placed after it, so attachments go last.
  (cd "$repo" && exec opencode run --agent "$agent" --dir "$repo" --auto --print-logs --log-level ERROR \
    "$1" ${files[@]+"${files[@]}"}) > "$tmp/out" 2> "$tmp/err" &
  pid=$!; launched=1
  while kill -0 "$pid" 2>/dev/null; do
    grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(reason)"
    [ "$(date +%s)" -ge "$end" ] && unavailable "timeout after ${DEEPSEEK_TIMEOUT:-580}s"
    sleep 1
  done
  wait "$pid"; code=$?; pid=
  grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(reason)"
  [ "$code" -eq 0 ] || unavailable "opencode exited $code: $(grep -v '^\s*$' "$tmp/err" | tail -1 | cut -c1-200)"
  cat "$tmp/out" >> "$tmp/all"
}
# The worker has no shell, so the script runs the task's `Test:` command for it (the command comes from the
# caller's packet, not the model) and sends one failure back for a correction round.
# ponytail: accepted risk — tests execute the worker's unreviewed code with the caller's permissions (secrets,
# network, files outside Scope), which the no-shell agent otherwise prevents; a bwrap/container sandbox is the upgrade.
runtests() {
  left=$(( end - $(date +%s) )); [ "$left" -gt 0 ] || left=1
  (cd "$repo" && timeout --kill-after=5 "$left" bash -c "$testcmd") > "$tmp/raw" 2>&1; rc=$?
  # test output goes back to the model: blank out every value (8+ chars) found in the repo's .env files
  # ponytail: exact-value match only, a test printing an encoded/partial secret still leaks; sandbox is the upgrade
  # values: "quoted", 'quoted', or unquoted up to whitespace or an inline # comment
  find "$repo" -name '.env*' ! -name '*.example' -type f -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -exec sed -n -e 's/^[^#=]*=[[:space:]]*"\([^"]*\)".*/\1/p' -e "s/^[^#=]*=[[:space:]]*'\([^']*\)'.*/\1/p" \
      -e "s/^[^#=]*=[[:space:]]*\([^\"'[:space:]#][^[:space:]#]*\).*/\1/p" {} + > "$tmp/secrets" 2>/dev/null
  awk -v list="$tmp/secrets" 'FILENAME==list{if(length($0)>=8)s[$0];next}
    {for(v in s){o="";r=$0;while((i=index(r,v))>0){o=o substr(r,1,i-1)"[REDACTED]";r=substr(r,i+length(v))};$0=o r};print}' "$tmp/secrets" "$tmp/raw" > "$tmp/test"
  return $rc
}

task=$(cat "$tmp/task.md")
launch "$task"
testcmd=; [ "$mode" = run ] && testcmd=$(sed -n 's/^Test: *//p' "$tmp/task.md" | head -1)
if [ -n "$testcmd" ]; then
  if ! runtests; then
    echo "--- correction round" >> "$tmp/all"
    launch "$task

Your edit is already in the files, but the test command \`$testcmd\` fails:
$(tail -n 60 "$tmp/test")

Fix the code so it passes (change a test only if it contradicts the task), then give the report again."
    runtests && result=pass || result="FAIL after one correction round"
  else result=pass; fi
fi

tail -n 200 "$tmp/all"
[ -n "$testcmd" ] && { echo "--- tests (\`$testcmd\`): $result"; [ "$result" = pass ] || tail -n 40 "$tmp/test"; }
[ "$mode" = run ] && { echo "--- git status"; git -C "$repo" status --short; }
exit 0
