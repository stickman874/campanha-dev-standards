#!/usr/bin/env bash
# tests/template.test.sh — one rendered layout for everyone (0.5.0: no backends)
source "$(dirname "$0")/lib.sh"
C=(copier); command -v copier >/dev/null || { command -v uvx >/dev/null && C=(uvx copier) || { echo "  skip template render (no copier/uvx)"; exit 0; }; }
R=$PWD; P=$(mktemp -d); T=$P/fx
"${C[@]}" copy --trust --skip-tasks --defaults --data project_name=fx --data tenant=single --quiet "$R" "$T" >/dev/null 2>"$P/err" || { echo "  FAIL copier copy: $(tail -1 "$P/err")"; FAILS=$((FAILS+1)); rm -rf "$P"; finish; }
assert_exit 0 jq -e . "$T/.claude/settings.json"
! grep -rq '{%\|{{' "$T/.claude" "$T/AGENTS.md" "$T/CLAUDE.md" "$T/mise.toml" "$T/opencode.json" && echo "  ok  no jinja left" || { echo "  FAIL jinja left"; FAILS=$((FAILS+1)); }
assert_eq true "$(jq '.enabledPlugins["codex@openai-codex"]' "$T/.claude/settings.json")" "codex plugin on (spec review)"
assert_eq opus "$(jq -r .model "$T/.claude/settings.json")" "Claude orchestrator opus"
[ ! -e "$T/.claude/agents" ] && echo "  ok  no Claude project agents" || { echo "  FAIL .claude/agents rendered"; FAILS=$((FAILS+1)); }
assert_eq 5 "$(ls "$T/.opencode/agents" | wc -l | tr -d ' ')" "five opencode agents"
assert_eq orchestrator "$(jq -r .default_agent "$T/opencode.json")" "opencode default agent"
[ -f "$T/scripts/opencode.sh" ] && [ -f "$T/scripts/review.sh" ] && echo "  ok  runner ships next to review.sh" || { echo "  FAIL scripts missing"; FAILS=$((FAILS+1)); }
assert_contains "$(cat "$T/mise.toml")" '^OPENCODE_EXPERIMENTAL_LSP_TOOL = "true"' "LSP tool for interactive opencode"
assert_eq "" "$(grep -n 'core:worker\|core:rescue\|core:review\|core:handoff\|worker\.sh\|backend' "$T/AGENTS.md" "$T/CLAUDE.md" "$T/.copier-answers.yml")" "no obsolete references"
assert_contains "$(cat "$T/AGENTS.md")" '^## opencode' "opencode contract section"
assert_contains "$(cat "$T/AGENTS.md")" '^## Parallel work' "parallelise rule"
assert_contains "$(cat "$T/CLAUDE.md")" 'codex:codex-rescue' "spec/plan review by Codex"
[ "$(wc -l < "$T/AGENTS.md")" -le 150 ] && echo "  ok  AGENTS.md <= 150 lines" || { echo "  FAIL AGENTS.md too long"; FAILS=$((FAILS+1)); }
rm -rf "$P"; finish
