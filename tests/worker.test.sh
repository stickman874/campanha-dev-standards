#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
D="$PWD/plugins/core/scripts/worker.sh"
W=$(mktemp -d); mkdir -p "$W/bin" "$W/repo/.opencode/agents"
cp template/.opencode/agents/worker.md "$W/repo/.opencode/agents/"
git -C "$W/repo" init -q; echo a > "$W/repo/a.ts"; git -C "$W/repo" add .; git -C "$W/repo" -c user.name=t -c user.email=t@t commit -qm init
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
ev() { printf '%s\n' "$1"; }
tool() { ev '{"type":"tool_use","part":{"tool":"edit","state":{"status":"completed"}}}'; }
case $FAKE_MODE in
  ok)       tool; echo x > touched.txt; ev '{"type":"text","part":{"text":"Summary: done\nFiles:\n- touched.txt — created\n- ghost.ts — edited\nVerify: npm test\nPartial: false\nSensitiveSeen: none"}}';;
  nothing)  tool; tool; tool; ev '{"type":"text","part":{"text":"Summary: done\nFiles:\n- a.ts — edited"}}';;
  limit)    echo x > half.txt; echo 'level=ERROR error.error="AI_APICallError: usage limit"' >&2; sleep 30;;
esac
ev '{"type":"step_finish","part":{"tokens":{"total":5},"cost":0}}'
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
ws() { git -C "$W/repo" checkout -q -- .; git -C "$W/repo" clean -fdq; FAKE_MODE=$1 bash "$D" "${@:2}"; }

out=$(echo "Outcome: x" | ws ok "$W/repo" 2>/dev/null); code=$?
assert_eq 0 "$code" "success exits 0"
assert_contains "$out" 'Summary: done' "worker report returned"
assert_contains "$out" '?? touched.txt' "git status shows changes"
assert_contains "$(cat "$FAKE_ARGS")" '^worker$' "uses the worker agent"
assert_contains "$out" 'claimed but unchanged' "cross-check section present"
assert_contains "$out" '^ghost.ts$' "claimed file git did not see is listed"
printf '%s' "$out" | sed -n '/claimed but unchanged/,$p' | grep -q 'touched.txt' && { echo "  FAIL real change listed as missing"; FAILS=$((FAILS+1)); } || echo "  ok  real change not listed as missing"
out=$(echo x | ws nothing "$W/repo" 2>&1); code=$?
assert_eq 4 "$code" "wrote nothing: exit 4"; assert_contains "$out" 'wrote nothing (3 tool calls' "wrote nothing reported"
out=$(echo x | ws limit "$W/repo" 2>/dev/null); code=$?
assert_eq 3 "$code" "usage limit: exit 3"; assert_contains "$out" 'DEEPSEEK_UNAVAILABLE' "unavailable passed through"; assert_contains "$out" 'half.txt' "partial edits listed"
echo dirty >> "$W/repo/a.ts"; rm -f "$FAKE_ARGS"; out=$(echo x | FAKE_MODE=ok bash "$D" "$W/repo" 2>&1); code=$?
assert_eq 2 "$code" "dirty tree refused"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL launched on dirty tree"; FAILS=$((FAILS+1)); } || echo "  ok  not launched on dirty tree"
assert_exit 2 bash "$D" /nonexistent
rm -rf "$W"; finish
