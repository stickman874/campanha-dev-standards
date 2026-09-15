#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
D="$PWD/plugins/core/scripts/deepseek.sh"
W=$(mktemp -d)
mkdir -p "$W/bin" "$W/oc/plugins" "$W/oc/agents" "$W/repo"
: > "$W/oc/plugins/core-guard.js"; : > "$W/oc/agents/deepseek-worker.md"; : > "$W/oc/agents/deepseek-reviewer.md"
git -C "$W/repo" init -q; echo a > "$W/repo/a.ts"; git -C "$W/repo" add .; git -C "$W/repo" -c user.name=t -c user.email=t@t commit -qm init
base=$(git -C "$W/repo" rev-parse HEAD)
echo b >> "$W/repo/a.ts"; git -C "$W/repo" -c user.name=t -c user.email=t@t commit -qam change

# fake opencode: records its args (one per line) and any attached file, behaves per FAKE_MODE
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"; echo call >> "$FAKE_CALLS"
prev=; for a in "$@"; do [ "$prev" = -f ] && cp "$a" "$FAKE_ATTACH"; prev=$a; done
case $FAKE_MODE in
  ok)    echo "Summary: done"; echo x > touched.txt;;
  fix)   printf '%s' "$*" | grep -q 'fails:' && echo y > fixed.txt; echo "Summary: round";;
  limit) echo 'level=ERROR error.error="AI_APICallError: 5-hour usage limit reached. Resets in 39min."' >&2; sleep 30;;
  hang)  sleep 30;;
  fail)  echo "boom" >&2; exit 1;;
  editfail) echo x > half.txt; echo "Summary: half done"; echo 'error.error="AI_APICallError: 5-hour usage limit reached."' >&2; sleep 30;;
esac
EOF
chmod +x "$W/bin/opencode"
export PATH="$W/bin:$PATH" OPENCODE_CONFIG_DIR="$W/oc" FAKE_ARGS="$W/args" FAKE_ATTACH="$W/attached" FAKE_CALLS="$W/calls"
ds() { git -C "$W/repo" checkout -q -- .; git -C "$W/repo" clean -fdq; rm -f "$W/calls"; FAKE_MODE=$1 bash "$D" "${@:2}"; }  # each call starts from a clean tree
calls() { wc -l < "$W/calls" | tr -d ' '; }

out=$(printf 'Outcome: x\nTest: test -e touched.txt\n' | ds ok run "$W/repo")
assert_contains "$out" 'tests (`test -e touched.txt`): pass' "tests: script runs the Test command"
assert_eq 1 "$(calls)" "tests: passing first time needs no correction round"
out=$(printf 'Outcome: x\nTest: test -e fixed.txt\n' | ds fix run "$W/repo")
assert_contains "$out" '): pass' "tests: failure sent back, fixed in the correction round"
assert_eq 2 "$(calls)" "tests: exactly one correction round"
assert_contains "$(cat "$W/args")" 'test -e fixed.txt` fails:' "tests: correction message names the failing command"
out=$(printf 'Outcome: x\nTest: echo nope; false\n' | ds ok run "$W/repo")
assert_contains "$out" 'FAIL after one correction round' "tests: still failing is reported"
assert_contains "$out" 'nope' "tests: failing output shown"
assert_contains "$(cat "$W/args")" 'nope' "tests: failing output reaches the correction round (no secret files)"
assert_eq 2 "$(calls)" "tests: no retry loop"
start=$(date +%s); printf 'Outcome: x\nTest: trap "" TERM; while :; do sleep 1; done\n' | DEEPSEEK_TIMEOUT=3 ds ok run "$W/repo" >/dev/null
[ $(( $(date +%s) - start )) -lt 15 ] && echo "  ok  tests: a test ignoring SIGTERM is killed" || { echo "  FAIL tests: hung past the budget"; FAILS=$((FAILS+1)); }
printf 'API_KEY="sk-live-abcdef123456"\nexport DB_PASS=hunter2hunter2 # production\nTOKEN='"'"'tok-single-quoted'"'"'\n' > "$W/repo/.env"; echo .env > "$W/repo/.git/info/exclude"
out=$(printf 'Outcome: x\nTest: cat .env; false\n' | ds ok run "$W/repo")
case "$out$(cat "$W/args")" in *abcdef123456*|*hunter2hunter2*|*tok-single*) echo "  FAIL secret from .env reached the worker or output"; FAILS=$((FAILS+1));; *) echo "  ok  tests: .env values redacted (quoted, unquoted with comment)";; esac
assert_contains "$(cat "$W/args")" 'DB_PASS=\[REDACTED\] # production' "tests: redaction marker sent instead"
rm -f "$W/repo/.env" "$W/repo/.git/info/exclude"
out=$(echo "Outcome: x" | ds ok run "$W/repo")
case $out in *'--- tests'*) echo "  FAIL no Test line still ran tests"; FAILS=$((FAILS+1));; *) echo "  ok  no Test line: no tests run";; esac

out=$(echo "Outcome: x" | ds ok run "$W/repo"); code=$?
assert_eq 0 "$code" "run: success exits 0"
assert_contains "$out" 'Summary: done' "run: worker output returned"
assert_contains "$out" 'touched.txt' "run: git status shows what changed"
assert_contains "$(cat "$W/args")" '^deepseek-worker$' "run: uses the no-shell worker agent"
assert_contains "$(cat "$W/args")" '^--auto$' "run: unattended"

rm -f "$W/canary"
echo "Fix \`touch $W/canary\` and \$(touch $W/canary)" | ds ok run "$W/repo" >/dev/null
[ -e "$W/canary" ] && { echo "  FAIL task text was executed"; FAILS=$((FAILS+1)); } || echo "  ok  task text never executed"
assert_contains "$(cat "$W/args")" '$(touch' "task reaches opencode literally"

start=$(date +%s); out=$(echo "Outcome: x" | ds limit run "$W/repo"); code=$?
assert_eq 3 "$code" "usage limit: exit 3"
assert_contains "$out" 'DEEPSEEK_UNAVAILABLE: AI_APICallError: 5-hour usage limit' "usage limit: reason reported"
[ $(( $(date +%s) - start )) -lt 10 ] && echo "  ok  usage limit: gives up early" || { echo "  FAIL usage limit: waited too long"; FAILS=$((FAILS+1)); }

out=$(echo "Outcome: x" | DEEPSEEK_TIMEOUT=2 ds hang run "$W/repo"); code=$?
assert_eq 3 "$code" "hang: exit 3"
assert_contains "$out" 'timeout after 2s' "hang: timeout reported"

out=$(echo "Outcome: x" | ds editfail run "$W/repo"); code=$?
assert_eq 3 "$code" "edit then limit: exit 3"
assert_contains "$out" 'Summary: half done' "edit then limit: partial output handed back"
assert_contains "$out" 'half.txt' "edit then limit: changed files listed for reconciliation"
git -C "$W/repo" add -A && git -C "$W/repo" -c user.name=t -c user.email=t@t commit -qm "wip: deepseek partial" -m "Worker: deepseek"
out=$(echo "Outcome: finish the partial work" | FAKE_MODE=ok bash "$D" run "$W/repo"); code=$?
assert_eq 0 "$code" "correction round runs after a WIP commit"

out=$(echo "Outcome: x" | ds fail run "$W/repo"); assert_contains "$out" 'DEEPSEEK_UNAVAILABLE: opencode exited 1: boom' "crash: reported as unavailable"

out=$(echo "Outcome: x" | OPENCODE_CONFIG_DIR="$W/none" ds ok run "$W/repo"); code=$?
assert_eq 3 "$code" "no guard: exit 3"
assert_contains "$out" 'core guard or opencode deepseek-worker agent not installed' "no guard: never runs --auto ungated"

out=$(echo "focus: change" | ds ok review "$W/repo" "$base")
assert_contains "$(cat "$W/args")" '^deepseek-reviewer$' "review: uses the read-only reviewer agent"
assert_contains "$(cat "$W/attached")" '^+b$' "review: diff base...HEAD attached"
assert_eq "-f" "$(tail -2 "$W/args" | head -1)" "review: attachment passed after the message (-f would swallow it)"
assert_eq "focus: change" "$(tail -3 "$W/args" | head -1)" "review: message is the argument before -f"
rm -f "$W/attached"
echo "review the plan in docs/plan.md" | ds ok review "$W/repo" >/dev/null
[ -e "$W/attached" ] && { echo "  FAIL plan review attached a diff"; FAILS=$((FAILS+1)); } || echo "  ok  plan review: no diff attached"
out=$(echo "focus" | ds ok review "$W/repo" HEAD); assert_contains "$out" 'Findings: none (empty diff' "review: empty diff approves without calling the model"

git -C "$W/repo" checkout -q -- .; git -C "$W/repo" clean -fdq
echo dirty >> "$W/repo/a.ts"; rm -f "$W/args"
out=$(echo "Outcome: x" | FAKE_MODE=ok bash "$D" run "$W/repo" 2>&1); code=$?
assert_eq 2 "$code" "dirty tree: run refused"
[ -e "$W/args" ] && { echo "  FAIL dirty tree: worker launched"; FAILS=$((FAILS+1)); } || echo "  ok  dirty tree: worker never launched"
assert_eq dirty "$(tail -1 "$W/repo/a.ts")" "dirty tree: user edits untouched"
assert_contains "$out" 'commit or stash' "dirty tree: says how to proceed"

assert_exit 2 bash "$D" run /nonexistent
rm -rf "$W"
finish
