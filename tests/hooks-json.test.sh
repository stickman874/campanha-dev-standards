#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
j=plugins/core/hooks/hooks.json
assert_eq 3 "$(jq '.hooks.PreToolUse[0].hooks | length' $j)" "three Bash PreToolUse hooks"
assert_eq Bash "$(jq -r '.hooks.PreToolUse[0].matcher' $j)" "matcher Bash"
assert_contains "$(jq -r '.hooks.PreToolUse[0].hooks[].command' $j)" 'pre-push-gate.sh' "gate wired"
for f in plugins/core/hooks/*.sh; do assert_exit 0 bash -n "$f"; done
[ -f plugins/core/skills/codex-review/SKILL.md ] && echo "  ok  skill exists" || { echo "  FAIL skill"; FAILS=$((FAILS+1)); }
finish
