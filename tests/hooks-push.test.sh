#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
H=$PWD/plugins/core/hooks/pre-push-gate.sh
T=$(mktemp -d); cd "$T" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
sha=$(git rev-parse HEAD)
run() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$H"; }

assert_eq "" "$(run 'git status')" "ignores non-push"
assert_contains "$(run 'git push')" 'codex-review' "denies without review marker"
mkdir -p .git/campanha && touch .git/campanha/reviewed-$sha
assert_contains "$(run 'git push origin main')" 'doc-keeper' "denies without docs marker"
touch .git/campanha/docs-$sha
assert_eq "" "$(run 'git push')" "allows when markers present and no lefthook"
printf 'pre-push:\n  commands:\n    fail:\n      run: exit 1\n' > lefthook.yml
if command -v lefthook >/dev/null; then
  assert_contains "$(run 'git push')" 'pre-push' "denies when lefthook pre-push fails"
fi
cd - >/dev/null; rm -rf "$T"
finish
