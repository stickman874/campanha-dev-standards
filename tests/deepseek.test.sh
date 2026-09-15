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
printf '%s\n' "$@" > "$FAKE_ARGS"
prev=; for a in "$@"; do [ "$prev" = -f ] && cp "$a" "$FAKE_ATTACH"; prev=$a; done
case $FAKE_MODE in
  ok)    echo "Summary: done"; echo x > touched.txt;;
  limit) echo 'level=ERROR error.error="AI_APICallError: 5-hour usage limit reached. Resets in 39min."' >&2; sleep 30;;
  hang)  sleep 30;;
  fail)  echo "boom" >&2; exit 1;;
esac
EOF
chmod +x "$W/bin/opencode"
export PATH="$W/bin:$PATH" OPENCODE_CONFIG_DIR="$W/oc" FAKE_ARGS="$W/args" FAKE_ATTACH="$W/attached"
ds() { FAKE_MODE=$1 bash "$D" "${@:2}"; }

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

assert_exit 2 bash "$D" run /nonexistent
rm -rf "$W"
finish
