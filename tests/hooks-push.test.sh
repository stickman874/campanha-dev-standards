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
assert_eq "" "$(run 'git push')" "allows when markers present"

# gated forms: markers are present, so all of these must be allowed
for c in 'git  push' 'git push origin main' 'git -C /x push' 'cd x && git push' 'if true; then git push; fi'; do
  assert_eq "" "$(run "$c")" "gated + allowed: $c"
done

# not gated at all: never require markers, even with markers removed
rm -f .git/campanha/reviewed-$sha .git/campanha/docs-$sha
for c in 'git status' 'git pushx' 'git push --help' 'git push -n' 'git push --dry-run'; do
  assert_eq "" "$(run "$c")" "not gated: $c"
done

cd - >/dev/null; rm -rf "$T"
finish
