#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T=plugins/core/templates
for f in AGENTS.md CLAUDE.md README.md CHANGELOG.md SECURITY.md lefthook.yml \
  public/.well-known/security.txt .claude/settings.json \
  .claude/rules/database.md .claude/rules/api.md .claude/rules/frontend.md \
  docs/dev/architecture.md docs/dev/decisions/0000-template.md \
  docs/dev/how-to/deploy.md docs/dev/how-to/rollback.md docs/dev/how-to/rotate-secrets.md \
  docs/dev/how-to/restore-backup.md docs/dev/how-to/incident.md \
  docs/dev/reference/data-model.md docs/dev/reference/env-vars.md docs/dev/reference/endpoints.md \
  docs/dev/reference/integrations.md docs/dev/explanation/security.md \
  docs/dev/handoffs/.gitkeep docs/dev/specs/.gitkeep docs/dev/plans/.gitkeep docs/dev/research/.gitkeep \
  docs/product/roles.md docs/product/glossary.md docs/product/features/.gitkeep docs/product/manual/.gitkeep; do
  [ -f "$T/$f" ] && echo "  ok  $f" || { echo "  FAIL missing $f"; FAILS=$((FAILS+1)); }
done
assert_eq "@AGENTS.md" "$(head -1 $T/CLAUDE.md)" "CLAUDE.md imports AGENTS.md"
assert_eq true "$(jq -r '.enabledPlugins["core@campanha-dev-standards"]' $T/.claude/settings.json)" "settings enable plugin"
assert_contains "$(cat $T/.claude/rules/database.md)" 'paths:' "rules are path-scoped"
[ "$(wc -l < $T/AGENTS.md)" -le 180 ] && echo "  ok  AGENTS.md <= 180 lines" || { echo "  FAIL AGENTS.md too long"; FAILS=$((FAILS+1)); }
assert_contains "$(cat $T/docs/dev/how-to/deploy.md)" 'trivy sbom' "SBOM step in deploy runbook"
assert_eq 2 "$(jq -r '.permissions.deny | length' $T/.claude/settings.json)" ".permissions.deny has 2 entries"
finish
