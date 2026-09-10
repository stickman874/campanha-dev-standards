#!/usr/bin/env bash
# Installs the binaries the standard needs. Idempotent. `--check` only reports.
set -u
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
grep -q '.local/bin' ~/.profile ~/.bashrc ~/.zshrc 2>/dev/null || echo "note: add $BIN to your PATH"

check=${1:-}
have() { command -v "$1" >/dev/null 2>&1; }
status() { if have "$1"; then echo "ok       $1"; else echo "MISSING  $1"; fi; }
for t in lefthook gitleaks semgrep trivy codex node jq; do status "$t"; done
if have npx && npx --no-install playwright --version >/dev/null 2>&1; then echo "ok       playwright"; else echo "MISSING  playwright"; fi
[ "$check" = "--check" ] && exit 0

echo; echo "Installing missing tools…"

have jq || { command -v apt-get >/dev/null && sudo -n apt-get install -y jq; } || echo "attempting jq install failed"
have lefthook || npm install -g lefthook || echo "attempting lefthook install failed"
have gitleaks || { if have jq; then case "$(uname -s)-$(uname -m)" in Linux-x86_64) a=linux_x64;; Linux-aarch64) a=linux_arm64;; Darwin-arm64) a=darwin_arm64;; Darwin-x86_64) a=darwin_x64;; *) a=linux_x64;; esac; v=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r .tag_name | tr -d v); curl -sL "https://github.com/gitleaks/gitleaks/releases/download/v${v}/gitleaks_${v}_${a}.tar.gz" | tar -xz -C "$BIN" gitleaks; else echo "gitleaks: jq needed to resolve version; install jq first"; fi; } || echo "attempting gitleaks install failed"
have semgrep || { have uv && uv tool install semgrep || { curl -LsSf https://astral.sh/uv/install.sh | sh && uv tool install semgrep; } || { have pipx && pipx install semgrep; }; } || echo "attempting semgrep install failed"
have trivy || { curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "$BIN"; } || echo "attempting trivy install failed"
have codex || npm install -g @openai/codex || echo "attempting codex install failed"
npx --yes playwright install chrome >/dev/null 2>&1 && echo "ok       playwright chrome"

echo; echo "Checking final status…"
fails=0
for t in lefthook gitleaks semgrep trivy codex jq; do have "$t" || { echo "FAILED: $t not installed"; fails=$((fails+1)); }; done
have npx && npx --no-install playwright --version >/dev/null 2>&1 || { echo "FAILED: playwright"; fails=$((fails+1)); }

if [ $fails -gt 0 ]; then
	echo "some tools failed to install (see FAILED lines)"
	exit 1
fi

echo; echo "Now in Claude Code:"
echo "  /plugin marketplace add stickman874/campanha-dev-standards && /plugin install core@campanha-dev-standards"
echo "  /plugin marketplace add openai/codex-plugin-cc && /plugin install codex@openai-codex"
echo "  codex login   (in a terminal)"
