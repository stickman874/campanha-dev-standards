#!/usr/bin/env bash
# tests/backend.test.sh — the template renders cleanly for both backends
source "$(dirname "$0")/lib.sh"
C=(copier); command -v copier >/dev/null || { command -v uvx >/dev/null && C=(uvx copier) || { echo "  skip backend render (no copier/uvx)"; exit 0; }; }
R=$PWD; T=$(mktemp -d)
for b in opencode claude; do
  "${C[@]}" copy --trust --skip-tasks --defaults --data project_name=fx --data tenant=single --data backend=$b --quiet "$R" "$T/$b" >/dev/null 2>"$T/err" || { echo "  FAIL copier copy $b: $(tail -1 "$T/err")"; FAILS=$((FAILS+1)); continue; }
  assert_exit 0 jq -e . "$T/$b/.claude/settings.json"
  ! grep -rq '{%\|{{' "$T/$b/.claude" "$T/$b/AGENTS.md" "$T/$b/CLAUDE.md" "$T/$b/mise.toml" && echo "  ok  $b: no jinja left" || { echo "  FAIL $b: jinja left"; FAILS=$((FAILS+1)); }
done
assert_eq true "$(jq '.enabledPlugins["codex@openai-codex"]' "$T/opencode/.claude/settings.json")" "opencode: codex plugin on"
assert_eq null "$(jq '.enabledPlugins["codex@openai-codex"]' "$T/claude/.claude/settings.json")" "claude: no codex plugin"
assert_eq null "$(jq '.extraKnownMarketplaces["openai-codex"]' "$T/claude/.claude/settings.json")" "claude: no codex marketplace"
assert_eq opus "$(jq -r .model "$T/claude/.claude/settings.json")" "claude: orchestrator opus"
[ -d "$T/opencode/.opencode" ] && [ ! -d "$T/opencode/.claude/agents" ] && echo "  ok  opencode: .opencode agents only" || { echo "  FAIL opencode layout"; FAILS=$((FAILS+1)); }
[ ! -d "$T/claude/.opencode" ] && [ -f "$T/claude/.claude/agents/rescuer.md" ] && echo "  ok  claude: .claude/agents only" || { echo "  FAIL claude layout"; FAILS=$((FAILS+1)); }
assert_contains "$(cat "$T/claude/.copier-answers.yml")" '^backend: claude' "answers record the backend"
rm -rf "$T"; finish
