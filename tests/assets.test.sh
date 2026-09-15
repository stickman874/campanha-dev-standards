#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
for f in plugins/core/hooks/*.sh plugins/core/scripts/*.sh template/scripts/*.sh deploy/nightly/*.sh; do assert_exit 0 bash -n "$f"; done
for f in plugins/core/skills/*/SKILL.md plugins/core/agents/*.md plugins/core/commands/*.md template/.opencode/agents/*.md; do
  assert_eq "---" "$(head -1 "$f")" "frontmatter: $f"; assert_contains "$(head -6 "$f")" 'description:' "description: $f"
done
for f in .claude-plugin/marketplace.json plugins/core/.claude-plugin/plugin.json plugins/core/hooks/hooks.json template/.claude/settings.json; do assert_exit 0 jq -e . "$f"; done
assert_eq 2 "$(jq '.hooks.PreToolUse[0].hooks | length' plugins/core/hooks/hooks.json)" "two Bash hooks"
assert_eq ./plugins/core "$(jq -r '.plugins[0].source' .claude-plugin/marketplace.json)" "plugin source"
[ "$(wc -l < template/AGENTS.md)" -le 150 ] && echo "  ok  AGENTS.md <= 150 lines" || { echo "  FAIL AGENTS.md too long"; FAILS=$((FAILS+1)); }
assert_exit 0 python3 -c 'import yaml; yaml.safe_load(open("copier.yml"))'
finish
