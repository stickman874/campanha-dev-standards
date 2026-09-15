#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S=$PWD/template/scripts/review.sh; export OPENCODE_SH=$PWD/plugins/core/scripts/opencode.sh
cmp -s "$S" plugins/core/scripts/review.sh && echo "  ok  template and plugin review.sh identical" || { echo "  FAIL review.sh copies differ"; FAILS=$((FAILS+1)); }
W=$(mktemp -d); mkdir -p "$W/bin"
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
case ${FAKE_MODE:-approve} in
  approve)  j='{"verdict":"approve","findings":[]}';;
  block)    j='{"verdict":"block","findings":[{"severity":"high","file":"src/app/api/r.ts","line":3,"what":"no auth check","fix":"call requireUser()"}]}';;
  sneaky)   j='{"verdict":"approve","findings":[{"severity":"high","file":"a.ts","line":1,"what":"x","fix":"y"}]}';;
  prose)    j='Sure! Here is my review. {"verdict":"approve","findings":[{"severity":"low","file":"a.ts","line":1,"what":"nit","fix":"none"}]} Hope this helps.';;
  junk)     j='I could not review this.';;
  limit)    echo 'error.error="AI_APICallError: usage limit"' >&2; sleep 30;;
  pretty)   j=$(jq -n '{"verdict":"approve","findings":[{"severity":"low","file":"a.ts","line":1,"what":"nit","fix":"none"}]}');;
  fenced)   j=$(printf '```json\n%s\n```' "$(jq -n '{"verdict":"approve","findings":[{"severity":"low","file":"a.ts","line":1,"what":"nit","fix":"none"}]}')");;
esac
jq -nc --arg t "$j" '{type:"text",part:{text:$t}}'; echo '{"type":"step_finish","part":{"tokens":{"total":1},"cost":0}}'
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
T="$W/repo"; mkdir -p "$T/.opencode/agents"; cp template/.opencode/agents/reviewer.md "$T/.opencode/agents/"; cd "$T"; git init -q -b main
c() { git -c user.name=t -c user.email=t@t commit -qm "$1"; }
mkdir -p src; echo a > src/a.ts; git add -A; c init; git branch base
echo b >> src/a.ts; git add -A; c routine
stdin() { printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" "$(git rev-parse base)"; }

rm -f "$FAKE_ARGS"; out=$(stdin | FAKE_MODE=block bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "stdin routine range: skipped"; assert_contains "$out" 'routine diff' "says why"
[ -e "$FAKE_ARGS" ] && { echo "  FAIL routine range called opencode"; FAILS=$((FAILS+1)); } || echo "  ok  routine range never calls opencode"
out=$(FAKE_MODE=approve bash "$S" base 2>&1); code=$?
assert_eq 0 "$code" "explicit range: reviewed and approved"; assert_contains "$(cat "$FAKE_ARGS")" '^reviewer$' "reviewer agent"
assert_contains "$(cat "$FAKE_ARGS")" 'src/a.ts' "prompt lists changed files"; assert_contains "$(cat "$FAKE_ARGS")" '^+b$' "prompt carries the diff"
out=$(stdin | FAKE_MODE=block bash "$S" --all 2>&1); code=$?
assert_eq 1 "$code" "--all reviews routine ranges and blocks on block"; assert_contains "$out" '\[high\] src/app/api/r.ts:3 - no auth check - call requireUser()' "findings printed as lines"
mkdir -p "src/app/(app)/rh"; echo a > "src/app/(app)/rh/actions.ts"; git add -A; c action
out=$(stdin | FAKE_MODE=block bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "actions.ts (server action file) counts as sensitive"
mkdir -p src/app/api; echo h > src/app/api/r.ts; git add -A; c api
out=$(stdin | FAKE_MODE=approve bash "$S" 2>&1); code=$?; assert_eq 0 "$code" "sensitive range approved passes"; assert_contains "$out" "range=$(git rev-parse base)..$(git rev-parse HEAD)" "logs range"
out=$(stdin | FAKE_MODE=block bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "sensitive range blocked"
out=$(stdin | FAKE_MODE=sneaky bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "approve with a high finding = block"
out=$(stdin | FAKE_MODE=prose bash "$S" 2>&1); code=$?; assert_eq 0 "$code" "JSON inside prose is accepted"; assert_contains "$out" '\[low\] a.ts:1' "finding from prose-wrapped JSON printed"
out=$(stdin | FAKE_MODE=junk bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "no JSON = block"; assert_contains "$out" 'no valid JSON' "explains"
out=$(FAKE_MODE=pretty bash "$S" base 2>&1); code=$?; assert_eq 0 "$code" "pretty-printed multi-line JSON accepted"; assert_contains "$out" '\[low\] a.ts:1' "finding from pretty JSON printed"
out=$(FAKE_MODE=fenced bash "$S" base 2>&1); code=$?; assert_eq 0 "$code" "fenced multi-line JSON accepted"; assert_contains "$out" '\[low\] a.ts:1' "finding from fenced JSON printed"
out=$(stdin | FAKE_MODE=limit bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "reviewer unavailable = block"; assert_contains "$out" 'SKIP_REVIEW=1' "tells the human how to force"

# runner discovery: real cache layout is .../core/<version>/scripts/opencode.sh; the newest installed version wins over an older stub
W2=$(mktemp -d)
mkdir -p "$W2/.claude/plugins/cache/campanha-dev-standards/core/0.2.0/scripts" "$W2/.claude/plugins/cache/campanha-dev-standards/core/0.3.0/scripts"
printf '#!/usr/bin/env bash\nexit 99\n' > "$W2/.claude/plugins/cache/campanha-dev-standards/core/0.2.0/scripts/opencode.sh"
cp "$OPENCODE_SH" "$W2/.claude/plugins/cache/campanha-dev-standards/core/0.3.0/scripts/opencode.sh"
chmod +x "$W2/.claude/plugins/cache/campanha-dev-standards/core/0.2.0/scripts/opencode.sh" "$W2/.claude/plugins/cache/campanha-dev-standards/core/0.3.0/scripts/opencode.sh"
out=$(env -u OPENCODE_SH -u CLAUDE_PLUGIN_ROOT HOME="$W2" FAKE_MODE=approve bash "$S" base 2>&1); code=$?
assert_eq 0 "$code" "runner discovery finds the newest installed cache version, not the older 0.2.0 stub"
rm -rf "$W2"

rm -f "$FAKE_ARGS"; out=$(stdin | SKIP_REVIEW=1 FAKE_MODE=block bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "SKIP_REVIEW=1 passes"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL SKIP_REVIEW called opencode"; FAILS=$((FAILS+1)); } || echo "  ok  SKIP_REVIEW never calls opencode"
assert_contains "$(cat docs/dev/reviews/skipped.log)" "$(git rev-parse HEAD)" "skipped range logged"
assert_contains "$out" 'commit docs/dev/reviews/skipped.log with your next commit' "tells the human to commit the skipped log"
printf 'refs/heads/f %s refs/heads/f %s\n' 0000000000000000000000000000000000000000 "$(git rev-parse HEAD)" | bash "$S" >/dev/null 2>&1; assert_eq 0 "$?" "deletion-only push passes"
out=$(printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef | FAKE_MODE=approve bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "unknown remote sha (local behind): reviewed against merge-base, not 'cannot diff'"; assert_contains "$out" 'range=' "unknown remote sha: a range was reviewed"
printf 'refs/heads/f %s refs/heads/f %s\n' "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 | FAKE_MODE=approve bash "$S" 2>&1 | grep -q 'range=4b825dc642cb6eb9a060e54bf8d69288fbee4904..' && echo "  ok  first push compared to the empty tree" || { echo "  FAIL first push base"; FAILS=$((FAILS+1)); }
git checkout -q base; git checkout -q -b same; rm -f "$FAKE_ARGS"; bash "$S" base >/dev/null 2>&1; code=$?
assert_eq 0 "$code" "empty diff passes"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL empty diff called opencode"; FAILS=$((FAILS+1)); } || echo "  ok  empty diff skips opencode"
git checkout -q main
head -c 130000 /dev/zero | tr '\0' a > big.ts; git add -A; c big
# review.sh's diff cap (CAP=100000) keeps the whole prompt (body + note + file list +
# instructions) well under the kernel's single-argv limit (MAX_ARG_STRLEN, 131072 bytes)
# that opencode.sh hits when it turns the prompt into a CLI argument for the real
# `opencode` binary, so the call reaches the fake reviewer normally: FAKE_MODE=approve
# means exit 0, and the fake's captured prompt (and stderr) both show the truncation.
rm -f "$FAKE_ARGS"; out=$(FAKE_MODE=approve bash "$S" base 2>&1); code=$?
assert_eq 0 "$code" "big diff, truncated but still reviewed and approved"
assert_contains "$out" 'diff truncated ([0-9]\+ bytes)' "stderr flags the truncation, with the real size"
assert_contains "$(cat "$FAKE_ARGS")" 'diff truncated' "prompt flags the truncation"
cd - >/dev/null; rm -rf "$W"; finish
