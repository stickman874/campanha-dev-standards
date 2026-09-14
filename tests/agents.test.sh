#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
a=plugins/core/agents/doc-keeper.md
assert_contains "$(head -8 $a)" 'name: doc-keeper' "agent name"
assert_contains "$(head -8 $a)" 'model: sonnet' "agent model"
for m in push bootstrap consolidate; do assert_contains "$(cat $a)" "## Mode: $m" "mode $m documented"; done
assert_contains "$(cat $a)" '/docs-$(git rev-parse HEAD)' "writes docs marker"
w=plugins/core/agents/deepseek-worker.md
assert_contains "$(head -6 $w)" 'name: deepseek-worker' "worker agent name"
assert_contains "$(cat $w)" 'DEEPSEEK_UNAVAILABLE' "worker signals fallback"
assert_contains "$(cat $w)" 'timeout 580' "worker cannot hang on silent retries"
assert_contains "$(cat $w)" 'core-guard.js' "worker refuses to run --auto without the guard"
assert_contains "$(cat $w)" '--agent deepseek-worker' "worker runs the no-shell opencode agent"
assert_contains "$(cat $w)" "<<'DEEPSEEK_TASK_END'" "task passed via quoted heredoc, never shell-expanded"
o=plugins/core/opencode/agents/deepseek-worker.md
assert_contains "$(cat $o)" 'bash: deny' "opencode worker agent has no shell"
assert_contains "$(cat $o)" 'task: deny' "opencode worker agent cannot spawn shell-capable subagents"
assert_contains "$(cat install.sh)" 'agents/deepseek-worker.md' "install.sh links the opencode worker agent"
assert_contains "$(cat plugins/core/templates/CLAUDE.md)" 'core:deepseek-worker' "template dispatches to worker"
finish
