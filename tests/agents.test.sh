#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
a=plugins/core/agents/doc-keeper.md
assert_contains "$(head -8 $a)" 'name: doc-keeper' "agent name"
assert_contains "$(head -8 $a)" 'model: sonnet' "agent model"
for m in diff bootstrap consolidate; do assert_contains "$(cat $a)" "## Mode: $m" "mode $m documented"; done
o=plugins/core/opencode/agents/deepseek-worker.md
assert_contains "$(cat $o)" 'bash: deny' "opencode worker agent has no shell"
assert_contains "$(cat $o)" 'task: deny' "opencode worker agent cannot spawn shell-capable subagents"
r=plugins/core/opencode/agents/deepseek-reviewer.md
assert_contains "$(cat $r)" 'edit: deny' "opencode reviewer agent cannot edit"
assert_contains "$(cat $r)" 'bash: deny' "opencode reviewer agent has no shell"
assert_contains "$(cat $o)" 'SensitiveSeen:' "worker report flags sensitive data"
assert_contains "$(cat install.sh)" 'agents/\*.md' "install.sh links every opencode agent"
[ -e plugins/core/agents/deepseek-worker.md ] && { echo "  FAIL relay subagent still shipped"; FAILS=$((FAILS+1)); } || echo "  ok  no relay subagent"
assert_contains "$(cat plugins/core/templates/CLAUDE.md)" 'core:deepseek-worker' "template dispatches to worker"
finish
