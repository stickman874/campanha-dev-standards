#!/usr/bin/env bash
# Installs the binaries the standard needs. Idempotent. `--check` only reports.
set -u
check=${1:-}
have() { command -v "$1" >/dev/null 2>&1; }
status() { if have "$1"; then echo "ok       $1"; else echo "MISSING  $1"; fi; }
for t in lefthook gitleaks semgrep trivy codex node jq; do status "$t"; done
if have npx && npx --no-install playwright --version >/dev/null 2>&1; then echo "ok       playwright"; else echo "MISSING  playwright"; fi
[ "$check" = "--check" ] && exit 0

echo; echo "Installing missing tools…"
have jq       || sudo apt-get install -y jq
have lefthook || npm install -g lefthook
have gitleaks || { v=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r .tag_name | tr -d v); curl -sL "https://github.com/gitleaks/gitleaks/releases/download/v${v}/gitleaks_${v}_linux_x64.tar.gz" | sudo tar -xz -C /usr/local/bin gitleaks; }
have semgrep  || { have pipx && pipx install semgrep || python3 -m pip install --user semgrep; }
have trivy    || { curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin; }
have codex    || npm install -g @openai/codex
npx --yes playwright install chrome >/dev/null 2>&1 && echo "ok       playwright chrome"
echo; echo "Now in Claude Code:"
echo "  /plugin marketplace add stickman874/campanha-dev-standards && /plugin install core@campanha-dev-standards"
echo "  /plugin marketplace add openai/codex-plugin-cc && /plugin install codex@openai-codex"
echo "  codex login   (in a terminal)"
