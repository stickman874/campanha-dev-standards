#!/usr/bin/env bash
# tests/claude.test.sh — claude.sh runner and the opencode.sh → claude.sh hand-over
source "$(dirname "$0")/lib.sh"
S="$PWD/plugins/core/scripts/claude.sh"; O="$PWD/plugins/core/scripts/opencode.sh"
W=$(mktemp -d); mkdir -p "$W/bin" "$W/repo/.claude/agents"
for a in worker rescuer reviewer docs; do cp "template/.claude/agents/$a.md" "$W/repo/.claude/agents/"; done
git -C "$W/repo" init -q
cat > "$W/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"; cat > "$FAKE_ARGS.stdin"
ev() { printf '%s\n' "$1"; }
case $FAKE_MODE in
  ok)    ev '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"},{"type":"text","text":"reading"}]}}'
         ev '{"type":"result","subtype":"success","is_error":false,"result":"Summary: done","total_cost_usd":0.02}';;
  limit) ev '{"type":"assistant","message":{"content":[{"type":"text","text":"partial"}]}}'
         ev '{"type":"result","subtype":"success","is_error":true,"result":"Claude AI usage limit reached"}';;
  hang)  sleep 30;;
  fail)  echo "Invalid API key - Please run /login" >&2; exit 1;;
esac
FAKE
chmod +x "$W/bin/claude"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
run() { FAKE_MODE=$1 bash "$S" "${@:2}"; }

out=$(echo "do x" | OPENCODE_EVENTS="$W/ev" run ok "$W/repo" worker 2> "$W/err"); code=$?
assert_eq 0 "$code" "ok exits 0"; assert_eq "Summary: done" "$out" "stdout is the final result only"
assert_contains "$(cat "$W/err")" 'claude: tools=1 cost=0.02' "summary on stderr"
a=$(cat "$FAKE_ARGS")
assert_contains "$a" '^-p$' "print mode"; assert_contains "$a" '^worker$' "agent passed"; assert_contains "$a" '^dontAsk$' "unlisted tools denied"
assert_contains "$a" '^--strict-mcp-config$' "no MCP servers"; assert_eq 0 "$(grep -c '^Bash' "$FAKE_ARGS")" "no Bash allowed"
assert_eq "do x" "$(cat "$FAKE_ARGS.stdin")" "prompt on stdin, not argv"
echo x | run ok "$W/repo" docs >/dev/null 2>&1; assert_contains "$(cat "$FAKE_ARGS")" '^Edit(docs/\*\*)$' "docs writes limited to docs/"
assert_eq 0 "$(grep -cx 'Edit' "$FAKE_ARGS")" "docs has no unrestricted Edit"
echo x | run ok "$W/repo" reviewer >/dev/null 2>&1; assert_eq 0 "$(grep -c '^Edit\|^Write' "$FAKE_ARGS")" "reviewer cannot write"
out=$(echo x | run limit "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "error result: exit 3"; assert_contains "$out" '^CLAUDE_UNAVAILABLE: .*usage limit' "reason first"; assert_contains "$out" 'usage limit' "result text returned"
out=$(echo x | OPENCODE_TIMEOUT=2 run hang "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "hang: exit 3"; assert_contains "$out" 'timeout after 2s' "timeout reported"
out=$(echo x | run fail "$W/repo" worker 2>/dev/null); assert_contains "$out" 'CLAUDE_UNAVAILABLE: claude exited 1: Invalid API key' "crash reported"
out=$(echo x | run ok "$W/repo" nosuch 2>/dev/null); code=$?; assert_eq 3 "$code" "missing agent file: exit 3"
assert_exit 2 bash "$S" /nonexistent worker
# hand-over: opencode.sh reads the backend from .copier-answers.yml
printf 'backend: claude\n' > "$W/repo/.copier-answers.yml"
out=$(echo x | FAKE_MODE=ok bash "$O" "$W/repo" reviewer 2>/dev/null); code=$?
assert_eq 0 "$code" "opencode.sh on backend claude runs claude.sh"; assert_contains "$(cat "$FAKE_ARGS")" '^reviewer$' "agent passed through"
rm "$W/repo/.copier-answers.yml"
out=$(echo x | CAMPANHA_BACKEND=claude FAKE_MODE=ok bash "$O" "$W/repo" worker 2>/dev/null); assert_eq "Summary: done" "$out" "CAMPANHA_BACKEND=claude also hands over"
rm -rf "$W"; finish
