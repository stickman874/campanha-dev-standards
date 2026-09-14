#!/usr/bin/env bash
# Deterministic half of /adopt: copy templates (never overwrite), substitute placeholders, install lefthook, report.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TPL="$ROOT/templates"
dir=${1:?usage: adopt.sh <project-dir> [--tenant single|multi]}; shift
tenant=single
while [ $# -gt 0 ]; do case "$1" in --tenant) tenant=$2; shift 2;; *) shift;; esac; done
cd "$dir" || exit 1
project=$(basename "$PWD")
esc() { printf '%s' "$1" | sed -e 's/[\/&\\#]/\\&/g'; }
p=$(esc "$project")

created=(); skipped=(); review=()
while IFS= read -r -d '' src; do
  rel=${src#"$TPL"/}
  if [ -e "$rel" ]; then skipped+=("$rel"); continue; fi
  mkdir -p "$(dirname "$rel")"
  sed -e "s/{{PROJECT}}/$p/g" -e "s/{{TENANT}}/$tenant/g" "$src" > "$rel"
  created+=("$rel")
done < <(find "$TPL" -type f -print0 | sort -z)

# vendor design-lint.sh into the project so lefthook.yml never references a
# machine-local plugin path (the previous CAMPANHA_PLUGIN_ROOT substitution
# broke for a second developer with a different cache path).
[ -e scripts/design-lint.sh ] || { mkdir -p scripts; cp "$ROOT/scripts/design-lint.sh" scripts/design-lint.sh; created+=("scripts/design-lint.sh"); }

# things a human / doc-keeper bootstrap must look at
[ -f CLAUDE.md ] && [ "$(wc -l < CLAUDE.md)" -gt 20 ] && review+=("CLAUDE.md ($(wc -l < CLAUDE.md) lines; move content to AGENTS.md / .claude/rules / docs)")
[ -f AGENTS.md ] && [ "$(wc -l < AGENTS.md)" -gt 180 ] && review+=("AGENTS.md (>180 lines)")
for f in PRD.md PRODUCT.md RESUMO_PROJETO.md handoff.md RESUME.md .claude/RESUME.md; do [ -e "$f" ] && review+=("$f (root doc; doc-keeper bootstrap distributes it)"); done
[ -d .planning ] && review+=(".planning (archive into docs/dev/research, then delete)")
ls docs 2>/dev/null | grep -vqE '^(dev|product)$' && review+=("docs/* outside dev|product (doc-keeper bootstrap)")
{ ls -d tests test __tests__ e2e 2>/dev/null | grep -q .; } || find . -path ./node_modules -prune -o -name '*.test.*' -print 2>/dev/null | grep -q . || review+=("no tests (pre-push will fail until a minimal suite exists)")
grep -Eq '"(vitest|jest|@playwright/test)"' package.json 2>/dev/null || review+=("no test runner in package.json")

# official Claude Code LSP plugins (code navigation + diagnostics after edits), enabled per stack marker
lsp=()
while IFS=: read -r markers plugin bin; do
  hit=; for m in ${markers//|/ }; do compgen -G "$m" >/dev/null && hit=1; done
  [ -n "$hit" ] || continue
  tmp=$(mktemp)
  if jq --arg p "$plugin@claude-plugins-official" '.enabledPlugins[$p] = true' .claude/settings.json > "$tmp" 2>/dev/null; then mv "$tmp" .claude/settings.json; lsp+=("$plugin")
  else rm -f "$tmp"; review+=("enable $plugin@claude-plugins-official in .claude/settings.json (jq missing or file unreadable)"); fi
  command -v "$bin" >/dev/null || review+=("install $bin (the $plugin plugin does nothing without it)")
done <<'EOF'
package.json|tsconfig.json:typescript-lsp:typescript-language-server
pyproject.toml|requirements.txt|setup.py:pyright-lsp:pyright-langserver
go.mod:gopls-lsp:gopls
Cargo.toml:rust-analyzer-lsp:rust-analyzer
composer.json:php-lsp:intelephense
*.csproj|*.sln:csharp-lsp:csharp-ls
pom.xml|build.gradle:jdtls-lsp:jdtls
Package.swift:swift-lsp:sourcekit-lsp
CMakeLists.txt|compile_commands.json:clangd-lsp:clangd
EOF

if command -v lefthook >/dev/null; then lefthook install >/dev/null 2>&1 && echo "lefthook: installed"; else echo "lefthook: NOT installed (run install.sh)"; fi
for x in ${created[@]+"${created[@]}"}; do echo "created: $x"; done
for x in ${skipped[@]+"${skipped[@]}"}; do echo "skipped (exists): $x"; done
for x in ${lsp[@]+"${lsp[@]}"};         do echo "lsp: $x"; done
for x in ${review[@]+"${review[@]}"};   do echo "needs-review: $x"; done
