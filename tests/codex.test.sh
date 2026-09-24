#!/usr/bin/env bash
# tests/codex.test.sh — codex.sh runner and the opencode.sh → codex.sh hand-over
source "$(dirname "$0")/lib.sh"
S="$PWD/plugins/core/scripts/codex.sh"; O="$PWD/plugins/core/scripts/opencode.sh"
W=$(mktemp -d); mkdir -p "$W/bin" "$W/repo/.claude/agents"
for a in worker reviewer docs; do cp "template/.claude/agents/$a.md" "$W/repo/.claude/agents/"; done
git -C "$W/repo" init -q
cat > "$W/bin/codex" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"; cat > "$FAKE_ARGS.stdin"
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
ev() { printf '%s\n' "$1"; }
case $FAKE_MODE in
  ok)    ev '{"type":"item.completed","item":{"type":"command_execution","command":"cat src/a.js"}}'
         ev '{"type":"item.completed","item":{"type":"agent_message","text":"Summary: done"}}'
         ev '{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":20}}'
         printf 'Summary: done' > "$out";;
  limit) ev '{"type":"item.completed","item":{"type":"agent_message","text":"partial"}}'
         ev '{"type":"turn.failed","error":{"message":"You have hit your usage limit"}}'; exit 1;;
  hang)  sleep 30;;
  fail)  echo "Not logged in" >&2; exit 1;;
esac
FAKE
cat > "$W/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' claude "$@" > "$FAKE_ARGS"; cat >/dev/null
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"docs done"}'
FAKE
chmod +x "$W/bin/codex" "$W/bin/claude"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
run() { FAKE_MODE=$1 bash "$S" "${@:2}"; }

out=$(echo "do x" | run ok "$W/repo" worker 2> "$W/err"); code=$?
assert_eq 0 "$code" "ok exits 0"; assert_eq "Summary: done" "$out" "stdout is the last message only"
assert_contains "$(cat "$W/err")" 'codex: tools=1 tokens=120' "summary on stderr"
a=$(cat "$FAKE_ARGS")
assert_contains "$a" '^gpt-6-sol$' "default model"; assert_contains "$a" '^workspace-write$' "worker can write"
assert_contains "$a" '^--ignore-user-config$' "no user MCP servers"; assert_contains "$a" 'windows.sandbox="unelevated"' "Windows sandbox that can read"
st=$(cat "$FAKE_ARGS.stdin")
assert_contains "$st" '^You are a worker' "agent instructions from .claude/agents"; assert_contains "$st" '^do x$' "task appended"
assert_eq 0 "$(grep -c '^model: haiku' "$FAKE_ARGS.stdin")" "frontmatter stripped"
echo x | CODEX_MODEL=gpt-6-luna run ok "$W/repo" reviewer >/dev/null 2>&1
assert_contains "$(cat "$FAKE_ARGS")" '^read-only$' "reviewer is read-only"; assert_contains "$(cat "$FAKE_ARGS")" '^gpt-6-luna$' "CODEX_MODEL overrides"
out=$(echo x | run limit "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "turn.failed: exit 3"; assert_contains "$out" '^CODEX_UNAVAILABLE: codex error: .*usage limit' "reason first"; assert_contains "$out" 'partial' "partial text returned"
out=$(echo x | OPENCODE_TIMEOUT=2 run hang "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "hang: exit 3"; assert_contains "$out" 'timeout after 2s' "timeout reported"
out=$(echo x | run fail "$W/repo" worker 2>/dev/null); assert_contains "$out" 'CODEX_UNAVAILABLE: codex exited 1: Not logged in' "crash reported"
out=$(echo x | run ok "$W/repo" nosuch 2>/dev/null); code=$?; assert_eq 3 "$code" "missing agent file: exit 3"
assert_exit 2 bash "$S" /nonexistent worker
# hand-over: backend codex → codex.sh, except docs → claude.sh
printf 'backend: codex\n' > "$W/repo/.copier-answers.yml"
out=$(echo x | FAKE_MODE=ok bash "$O" "$W/repo" reviewer 2>/dev/null); assert_eq "Summary: done" "$out" "opencode.sh on backend codex runs codex.sh"
out=$(echo x | FAKE_MODE=ok bash "$O" "$W/repo" docs 2>/dev/null); assert_eq "docs done" "$out" "docs stay on Claude"
rm -rf "$W"; finish
