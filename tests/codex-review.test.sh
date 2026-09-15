#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S=$PWD/template/scripts/codex-review.sh
W=$(mktemp -d); mkdir -p "$W/bin"
cat > "$W/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
last=/dev/null; while [ $# -gt 0 ]; do case $1 in -o) last=$2; shift;; esac; shift; done
{ echo "Findings: ${FAKE_FINDINGS:-none}"; echo "VERDICT: ${FAKE_VERDICT-approve}"; echo "${FAKE_TRAILER:-}"; } | tee "$last"
EOF
chmod +x "$W/bin/codex"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
T="$W/repo"; mkdir -p "$T"; cd "$T"; git init -q -b main
c() { git -c user.name=t -c user.email=t@t commit -qm "$1"; }
mkdir -p src; echo a > src/a.ts; git add -A; c init; git branch base
echo b >> src/a.ts; git add -A; c change

assert_exit 0 bash "$S" base
assert_contains "$(cat "$FAKE_ARGS")" '^exec$' "runs codex exec"
assert_contains "$(cat "$FAKE_ARGS")" '^read-only$' "read-only sandbox"
assert_contains "$(cat "$FAKE_ARGS")" 'changes between commits base and HEAD' "prompt names the range"
assert_contains "$(cat "$FAKE_ARGS")" '^gpt-5.6-sol$' "routine diff: sol"
assert_contains "$(cat "$FAKE_ARGS")" 'model_reasoning_effort="medium"' "routine diff: medium"
assert_contains "$(bash "$S" base 2>&1)" 'codex-review: model=gpt-5.6-sol' "logs model"

out=$(FAKE_VERDICT=block bash "$S" base 2>&1); code=$?
assert_eq 1 "$code" "block verdict fails the push"
assert_contains "$out" 'VERDICT: block' "shows the review"
out=$(FAKE_VERDICT="" FAKE_FINDINGS="x" bash "$S" base 2>&1); code=$?
[ "$code" -ne 0 ] && echo "  ok  missing verdict fails closed" || { echo "  FAIL missing verdict passed"; FAILS=$((FAILS+1)); }

# hook (stdin) ranges: a routine diff is skipped, even without codex
rm -f "$FAKE_ARGS"; out=$(printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" "$(git rev-parse base)" | PATH=/usr/bin:/bin FAKE_VERDICT=block bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "stdin routine diff: skipped"
assert_contains "$out" 'routine diff' "stdin routine diff: says why"
[ -e "$FAKE_ARGS" ] && { echo "  FAIL stdin routine diff called codex"; FAILS=$((FAILS+1)); } || echo "  ok  stdin routine diff skips codex"
mkdir -p src/app/api; echo h > src/app/api/r.ts; git add -A; c api
bash "$S" base >/dev/null 2>&1
assert_contains "$(cat "$FAKE_ARGS")" '^gpt-6-astra$' "sensitive diff: astra"
CODEX_REVIEW_MODEL=x CODEX_REVIEW_EFFORT=low bash "$S" base >/dev/null 2>&1
assert_contains "$(cat "$FAKE_ARGS")" '^x$' "env override wins"

out=$(FAKE_VERDICT=approve FAKE_TRAILER="VERDICT: block" bash "$S" base 2>&1); code=$?
assert_eq 1 "$code" "only the last line decides (approve then block = block)"
# ranges from git's pre-push stdin: pushing a feature branch while HEAD has nothing new vs upstream
feat=$(git rev-parse HEAD); git checkout -q base
out=$(printf 'refs/heads/feat %s refs/heads/feat %s\n' "$feat" "$(git rev-parse base)" | FAKE_VERDICT=block bash "$S" 2>&1); code=$?
assert_eq 1 "$code" "stdin ranges: pushed ref is reviewed even when HEAD is clean"
assert_contains "$out" "range=$(git rev-parse base)..$feat" "stdin ranges: logs the pushed range"
out=$(printf 'refs/heads/feat %s refs/heads/feat %s\n' "$feat" "$(git rev-parse base)" | bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "stdin ranges: approve passes"
rm -f "$FAKE_ARGS"; printf 'refs/heads/f %s refs/heads/f %s\n' 0000000000000000000000000000000000000000 "$feat" | bash "$S" >/dev/null 2>&1; code=$?
assert_eq 0 "$code" "deletion-only push passes"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL deletion-only push called codex"; FAILS=$((FAILS+1)); } || echo "  ok  deletion-only push skips codex"
out=$(printf 'refs/heads/f %s refs/heads/f %s\n' "$feat" "$(git rev-parse base)" | FAKE_VERDICT=block bash "$S" 2>&1); code=$?
assert_eq 1 "$code" "rollback push is reviewed (trees compared directly)"
out=$(printf 'refs/heads/f %s refs/heads/f %s\n' "$feat" 0000000000000000000000000000000000000000 | bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "first push to an empty remote does not fail"
assert_contains "$out" 'range=4b825dc642cb6eb9a060e54bf8d69288fbee4904..' "first push: compared against the empty tree"
git checkout -q base; git checkout -q -b same
assert_exit 0 bash "$S" base   # empty diff: no codex call
rm -f "$FAKE_ARGS"; bash "$S" base >/dev/null 2>&1; [ -e "$FAKE_ARGS" ] && { echo "  FAIL empty diff called codex"; FAILS=$((FAILS+1)); } || echo "  ok  empty diff skips codex"
git checkout -q main
PATH=/usr/bin:/bin bash "$S" base >/dev/null 2>&1; code=$?
assert_eq 1 "$code" "missing codex blocks"
cd - >/dev/null; rm -rf "$W"; finish
