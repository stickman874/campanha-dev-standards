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
assert_contains "$(cat plugins/core/templates/CLAUDE.md)" 'core:deepseek-worker' "template dispatches to worker"
finish
