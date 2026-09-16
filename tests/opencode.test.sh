#!/usr/bin/env bash
# tests/opencode.test.sh
source "$(dirname "$0")/lib.sh"
S="$PWD/plugins/core/scripts/opencode.sh"
W=$(mktemp -d); mkdir -p "$W/bin" "$W/repo/.opencode/agents"
printf -- '---\ndescription: t\n---\n' > "$W/repo/.opencode/agents/worker.md"
git -C "$W/repo" init -q
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"; echo "LSP=$OPENCODE_EXPERIMENTAL_LSP_TOOL" >> "$FAKE_ARGS"
ev() { printf '%s\n' "$1"; }
case $FAKE_MODE in
  ok)    ev '{"type":"step_start"}'; ev '{"type":"tool_use","part":{"tool":"read","state":{"status":"completed"}}}'
         ev '{"type":"text","part":{"text":"Summary: done"}}'; ev '{"type":"step_finish","part":{"tokens":{"total":120},"cost":0.001}}';;
  limit) ev '{"type":"text","part":{"text":"partial"}}'; echo 'level=ERROR error.error="AI_APICallError: 5-hour usage limit reached."' >&2; sleep 30;;
  errev) ev '{"type":"error","error":{"message":"FreeUsageLimitError: free usage exceeded"}}';;
  hang)  sleep 30;;
  stubborn) trap '' TERM; sleep 30;;
  fail)  echo boom >&2; exit 1;;
esac
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
run() { FAKE_MODE=$1 bash "$S" "${@:2}"; }

out=$(echo "do x" | OPENCODE_EVENTS="$W/ev" run ok "$W/repo" worker 2> "$W/err"); code=$?
assert_eq 0 "$code" "ok exits 0"
assert_eq "Summary: done" "$out" "stdout is the final text only"
assert_contains "$(cat "$W/err")" 'opencode: tools=1 tokens=120 cost=0.001' "summary on stderr"
assert_eq 1 "$(jq -c 'select(.type=="tool_use")' "$W/ev" | wc -l)" "events saved to OPENCODE_EVENTS"
a=$(cat "$FAKE_ARGS")
assert_contains "$a" '^--format$' "json format"; assert_contains "$a" '^json$' "json format value"
assert_contains "$a" '^worker$' "agent passed"; assert_contains "$a" '^--auto$' "unattended"; assert_contains "$a" 'LSP=true' "LSP enabled"
echo x | OPENCODE_MODEL=p/m run ok "$W/repo" worker >/dev/null 2>&1; assert_contains "$(cat "$FAKE_ARGS")" '^p/m$' "OPENCODE_MODEL adds -m"
echo x | run ok "$W/repo" worker >/dev/null 2>&1; assert_eq 0 "$(grep -c '^-m$' "$FAKE_ARGS")" "no -m without OPENCODE_MODEL"
rm -f "$W/canary"; echo "Fix \`touch $W/canary\` and \$(touch $W/canary)" | run ok "$W/repo" worker >/dev/null 2>&1
[ -e "$W/canary" ] && { echo "  FAIL prompt text executed"; FAILS=$((FAILS+1)); } || echo "  ok  prompt text never executed"
start=$(date +%s); out=$(echo x | run limit "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "usage limit: exit 3"; assert_contains "$out" '^DEEPSEEK_UNAVAILABLE: .*usage limit' "reason first"; assert_contains "$out" 'partial' "partial text returned"
[ $(( $(date +%s) - start )) -lt 10 ] && echo "  ok  gives up early" || { echo "  FAIL waited"; FAILS=$((FAILS+1)); }
out=$(echo x | run errev "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "error event: exit 3"; assert_contains "$out" 'FreeUsageLimitError' "error event message reported"
out=$(echo x | OPENCODE_TIMEOUT=2 run hang "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "hang: exit 3"; assert_contains "$out" 'timeout after 2s' "timeout reported"
start=$(date +%s); out=$(echo x | OPENCODE_TIMEOUT=2 run stubborn "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "stubborn (ignores TERM): exit 3"
[ $(( $(date +%s) - start )) -lt 12 ] && echo "  ok  kills stubborn process within budget" || { echo "  FAIL waited too long for stubborn kill"; FAILS=$((FAILS+1)); }
out=$(echo x | run fail "$W/repo" worker 2>/dev/null); assert_contains "$out" 'DEEPSEEK_UNAVAILABLE: opencode exited 1' "crash reported"
out=$(echo x | run ok "$W/repo" nosuch 2>/dev/null); code=$?; assert_eq 3 "$code" "missing agent file: exit 3"; assert_contains "$out" 'nosuch.md missing' "names the agent file"
clean_path=$(IFS=:; for d in $PATH; do [ "$d" = "$W/bin" ] && continue; printf '%s:' "$d"; done)
out=$(echo x | PATH="${clean_path%:}" run ok "$W/repo" worker 2>/dev/null); code=$?; assert_eq 3 "$code" "missing opencode: exit 3"
assert_exit 2 bash "$S" /nonexistent worker
printf '' | run ok "$W/repo" worker >/dev/null 2>&1; assert_eq 2 "$?" "empty prompt: exit 2"
rm -rf "$W"; finish
