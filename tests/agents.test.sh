#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
a=plugins/core/agents/doc-keeper.md
assert_contains "$(head -8 $a)" 'name: doc-keeper' "agent name"
assert_contains "$(head -8 $a)" 'model: sonnet' "agent model"
for m in diff bootstrap consolidate; do assert_contains "$(cat $a)" "## Mode: $m" "mode $m documented"; done
o=plugins/core/templates/.opencode/agents/deepseek-worker.md
assert_contains "$(cat $o)" 'bash: deny' "opencode worker agent has no shell"
assert_contains "$(cat $o)" 'task: deny' "opencode worker agent cannot spawn shell-capable subagents"
assert_contains "$(cat $o)" 'SensitiveSeen:' "worker report flags sensitive data"
[ -e plugins/core/agents/deepseek-worker.md ] && { echo "  FAIL relay subagent still shipped"; FAILS=$((FAILS+1)); } || echo "  ok  no relay subagent"
assert_contains "$(cat plugins/core/templates/CLAUDE.md)" 'core:worker' "template dispatches to worker"
finish
