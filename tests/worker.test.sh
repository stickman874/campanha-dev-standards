#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
D="$PWD/plugins/core/scripts/worker.sh"
W=$(mktemp -d); mkdir -p "$W/bin" "$W/repo/.opencode/agents"
cp plugins/core/templates/.opencode/agents/deepseek-worker.md "$W/repo/.opencode/agents/"
git -C "$W/repo" init -q; echo a > "$W/repo/a.ts"; git -C "$W/repo" add .; git -C "$W/repo" -c user.name=t -c user.email=t@t commit -qm init
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"; echo "LSP=$OPENCODE_EXPERIMENTAL_LSP_TOOL" >> "$FAKE_ARGS"
case $FAKE_MODE in
  ok)    echo "Summary: done"; echo x > touched.txt;;
  limit) echo 'level=ERROR error.error="AI_APICallError: 5-hour usage limit reached."' >&2; sleep 30;;
  hang)  sleep 30;;
  fail)  echo "boom" >&2; exit 1;;
  editfail) echo x > half.txt; echo "Summary: half"; echo 'error.error="AI_APICallError: usage limit"' >&2; sleep 30;;
esac
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
ws() { git -C "$W/repo" checkout -q -- .; git -C "$W/repo" clean -fdq; FAKE_MODE=$1 bash "$D" "${@:2}"; }

out=$(echo "Outcome: x" | ws ok "$W/repo"); code=$?
assert_eq 0 "$code" "success exits 0"
assert_contains "$out" 'Summary: done' "worker output returned"
assert_contains "$out" 'touched.txt' "git status shows changes"
assert_contains "$(cat "$FAKE_ARGS")" '^deepseek-worker$' "uses the no-shell agent"
assert_contains "$(cat "$FAKE_ARGS")" '^--auto$' "unattended"
assert_contains "$(cat "$FAKE_ARGS")" 'LSP=true' "LSP tool enabled for the worker"
rm -f "$W/canary"; echo "Fix \`touch $W/canary\` and \$(touch $W/canary)" | ws ok "$W/repo" >/dev/null
[ -e "$W/canary" ] && { echo "  FAIL task text executed"; FAILS=$((FAILS+1)); } || echo "  ok  task text never executed"
start=$(date +%s); out=$(echo x | ws limit "$W/repo"); code=$?
assert_eq 3 "$code" "usage limit: exit 3"; assert_contains "$out" 'DEEPSEEK_UNAVAILABLE: AI_APICallError' "reason reported"
[ $(( $(date +%s) - start )) -lt 10 ] && echo "  ok  gives up early" || { echo "  FAIL waited"; FAILS=$((FAILS+1)); }
out=$(echo x | WORKER_TIMEOUT=2 ws hang "$W/repo"); code=$?
assert_eq 3 "$code" "hang: exit 3"; assert_contains "$out" 'timeout after 2s' "timeout reported"
out=$(echo x | ws editfail "$W/repo"); assert_contains "$out" 'half.txt' "partial edits listed"
out=$(echo x | ws fail "$W/repo"); assert_contains "$out" 'DEEPSEEK_UNAVAILABLE: opencode exited 1' "crash reported"
git -C "$W/repo" rm -q .opencode/agents/deepseek-worker.md && git -C "$W/repo" -c user.name=t -c user.email=t@t commit -qm "no agent"; out=$(echo x | ws ok "$W/repo"); code=$?
assert_eq 3 "$code" "missing project agent: exit 3"; git -C "$W/repo" reset -q --hard HEAD~1
assert_eq 3 "$code" "missing project agent: exit 3"; cp plugins/core/templates/.opencode/agents/deepseek-worker.md "$W/repo/.opencode/agents/"
echo dirty >> "$W/repo/a.ts"; rm -f "$FAKE_ARGS"; out=$(echo x | FAKE_MODE=ok bash "$D" "$W/repo" 2>&1); code=$?
assert_eq 2 "$code" "dirty tree refused"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL launched on dirty tree"; FAILS=$((FAILS+1)); } || echo "  ok  not launched on dirty tree"
assert_exit 2 bash "$D" /nonexistent
rm -rf "$W"; finish
