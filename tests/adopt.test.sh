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
assert_contains "$(cat lefthook.yml)" "$ROOT/scripts/design-lint.sh" "plugin root resolved in lefthook.yml"
[ -f docs/dev/architecture.md ] && echo "  ok  docs tree" || { echo "  FAIL docs tree"; FAILS=$((FAILS+1)); }
[ -f .claude/rules/database.md ] && echo "  ok  rules" || { echo "  FAIL rules"; FAILS=$((FAILS+1)); }
out2=$(bash "$A" "$T"); assert_contains "$out2" 'skipped (exists): AGENTS.md' "idempotent"
cd - >/dev/null; rm -rf "$(dirname "$T")"; finish
