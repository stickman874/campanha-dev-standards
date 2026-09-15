#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
for s in handoff codex-review deepseek-worker; do
  f=plugins/core/skills/$s/SKILL.md
  assert_contains "$(head -5 $f)" "name: $s" "skill $s frontmatter"
  assert_contains "$(head -5 $f)" 'description:' "skill $s description"
done
assert_contains "$(cat plugins/core/skills/handoff/SKILL.md)" 'docs/dev/handoffs/' "handoff path"
finish
