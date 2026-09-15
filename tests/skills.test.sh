#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
for s in security-posture handoff codex-review deepseek-worker; do
  f=plugins/core/skills/$s/SKILL.md
  assert_contains "$(head -5 $f)" "name: $s" "skill $s frontmatter"
  assert_contains "$(head -5 $f)" 'description:' "skill $s description"
done
assert_contains "$(cat plugins/core/skills/handoff/SKILL.md)" 'docs/dev/handoffs/' "handoff path"
assert_contains "$(cat plugins/core/skills/security-posture/SKILL.md)" 'Personal data' "GDPR item"
c=plugins/core/skills/codex-review/SKILL.md
assert_contains "$(cat $c)" 'Codex, required' "review: Codex required for sensitive diffs"
assert_contains "$(cat $c)" 'deepseek.sh" review' "review: DeepSeek runs through the script"
assert_contains "$(cat $c)" '--scope branch' "review: Codex always gets a base"
k=plugins/core/skills/deepseek-worker/SKILL.md
assert_contains "$(cat $k)" 'deepseek.sh" run' "worker skill runs the script"
assert_contains "$(cat $k)" 'Acceptance:' "worker skill defines the task packet"
assert_contains "$(cat $k)" 'Worker: deepseek' "worker skill marks commits with DeepSeek-written code"
assert_contains "$(cat $k)" 'wip: deepseek partial' "worker skill: correction round starts from a WIP commit"
assert_contains "$(cat $c)" "grep='^Worker: deepseek'" "review: DeepSeek-written diffs go to Codex"
finish
