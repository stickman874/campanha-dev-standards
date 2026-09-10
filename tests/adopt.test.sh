#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
A=$PWD/plugins/core/scripts/adopt.sh
ROOT=$PWD/plugins/core
T=$(mktemp -d)/my-app; mkdir -p "$T"; cd "$T"; git init -q
printf 'line\n%.0s' $(seq 1 40) > CLAUDE.md          # oversized existing CLAUDE.md
echo "# PRD" > PRD.md; mkdir -p .planning
out=$(bash "$A" "$T" --tenant multi)
assert_contains "$out" 'created: AGENTS.md' "creates AGENTS.md"
assert_contains "$out" 'skipped (exists): CLAUDE.md' "never overwrites"
assert_contains "$out" 'needs-review: CLAUDE.md' "flags oversized CLAUDE.md"
assert_contains "$out" 'needs-review: PRD.md' "flags root docs"
assert_contains "$out" 'needs-review: .planning' "flags .planning"
assert_contains "$out" 'needs-review: no tests' "flags missing tests"
assert_contains "$(cat AGENTS.md)" '# my-app' "project name substituted"
assert_contains "$(cat AGENTS.md)" 'Tenant model: multi' "tenant substituted"
[ -f scripts/design-lint.sh ] && echo "  ok  design-lint.sh vendored" || { echo "  FAIL design-lint.sh not vendored"; FAILS=$((FAILS+1)); }
assert_contains "$(cat lefthook.yml)" 'bash scripts/design-lint.sh' "lefthook.yml references vendored script"
[ -f docs/dev/architecture.md ] && echo "  ok  docs tree" || { echo "  FAIL docs tree"; FAILS=$((FAILS+1)); }
[ -f .claude/rules/database.md ] && echo "  ok  rules" || { echo "  FAIL rules"; FAILS=$((FAILS+1)); }
out2=$(bash "$A" "$T"); assert_contains "$out2" 'skipped (exists): AGENTS.md' "idempotent"
cd - >/dev/null; rm -rf "$(dirname "$T")"

T2=$(mktemp -d)/a\&b; mkdir -p "$T2"; cd "$T2"; git init -q
bash "$A" "$T2" >/dev/null
assert_contains "$(cat AGENTS.md)" '# a&b' "project name with & escaped correctly"
cd - >/dev/null; rm -rf "$(dirname "$T2")"
finish
