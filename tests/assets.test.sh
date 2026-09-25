#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
for f in plugins/core/hooks/*.sh plugins/core/scripts/*.sh template/scripts/*.sh deploy/nightly/*.sh; do assert_exit 0 bash -n "$f"; done
for f in plugins/core/agents/*.md plugins/core/commands/*.md template/.opencode/agents/*.md; do
  assert_eq "---" "$(head -1 "$f")" "frontmatter: $f"; assert_contains "$(head -6 "$f")" 'description:' "description: $f"
done
for f in .claude-plugin/marketplace.json plugins/core/.claude-plugin/plugin.json plugins/core/hooks/hooks.json template/.claude/settings.json template/opencode.json; do assert_exit 0 jq -e . "$f"; done
assert_eq 2 "$(jq '.hooks.PreToolUse[0].hooks | length' plugins/core/hooks/hooks.json)" "two Bash hooks"
assert_eq ./plugins/core "$(jq -r '.plugins[0].source' .claude-plugin/marketplace.json)" "plugin source"
assert_eq 0.5.4 "$(jq -r .version plugins/core/.claude-plugin/plugin.json)" "version 0.5.4"
[ ! -e plugins/core/skills ] && echo "  ok  plugin ships no skills" || { echo "  FAIL plugins/core/skills still exists"; FAILS=$((FAILS+1)); }
assert_eq "" "$(grep -rln 'core:worker\|core:rescue\|core:review\|core:handoff\|worker\.sh\|claude\.sh\|codex\.sh\|backend' plugins template deploy .claude-plugin)" "no obsolete references in shipped files"
PY=python3; command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1 || PY=python   # Windows ships only `python` (python3 may be a Store-alias stub)
assert_exit 0 "$PY" -c 'import yaml; yaml.safe_load(open("copier.yml"))'
finish
