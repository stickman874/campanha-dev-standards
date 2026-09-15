#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S=$PWD/template/scripts/docs-check.sh
T=$(mktemp -d); cd "$T"; git init -q -b main
c() { git -c user.name=t -c user.email=t@t commit -qm "$1"; }
mkdir -p src docs; echo a > src/a.ts; echo d > docs/d.md; git add -A; c init
git branch base
echo b >> src/a.ts; git add -A; c "code only"
assert_exit 1 bash "$S" base
assert_contains "$(bash "$S" base 2>&1)" 'doc-keeper' "names the fix"
echo dd >> docs/d.md; git add -A; c "docs too"
assert_exit 0 bash "$S" base
code_only=$(git rev-parse HEAD~1); git checkout -q base
printf 'refs/heads/f %s refs/heads/f %s\n' "$code_only" "$(git rev-parse base)" | bash "$S" >/dev/null 2>&1; code=$?
assert_eq 1 "$code" "stdin range: pushed code-only ref blocked while HEAD is clean"
git checkout -q base; git checkout -q -b readme; echo r > README.md; git add -A; c "readme only"
assert_exit 0 bash "$S" base
cd - >/dev/null; rm -rf "$T"; finish
