#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
export PATH="$HOME/.local/bin:$PATH"
command -v lefthook >/dev/null && command -v gitleaks >/dev/null || { echo "  skip e2e (lefthook or gitleaks missing; run install.sh)"; exit 0; }

R=$PWD; T=$(mktemp -d)/fixture; mkdir -p "$T"; cd "$T"; git init -q
printf '{"name":"fixture","scripts":{"test":"echo tests-ok"},"devDependencies":{}}\n' > package.json
bash "$R/plugins/core/scripts/adopt.sh" "$T" --tenant single >/dev/null

# The fixture never runs `npm install`, so eslint isn't available and the
# `lint` pre-commit command (`npx eslint {staged_files}`) would fail on any
# staged .ts/.tsx regardless of content. Drop it here so the test exercises
# gitleaks and design-lint (the commands under test), not a missing eslint.
sed -i '/^    lint:/,/^      run:/d' lefthook.yml

git add -A && git -c user.name=t -c user.email=t@t commit -qm "chore: adopt" && echo "  ok  adopt commit passes pre-commit" || { echo "  FAIL adopt commit blocked"; FAILS=$((FAILS+1)); }

echo '<div style={{color:"#123"}}/>' > bad.tsx; git add bad.tsx
if git -c user.name=t -c user.email=t@t commit -qm "bad" >/dev/null 2>&1; then echo "  FAIL design lint did not block"; FAILS=$((FAILS+1)); else echo "  ok  design lint blocks commit"; fi
git reset -q HEAD bad.tsx; rm -f bad.tsx

out=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push"}}' | bash "$R/plugins/core/hooks/pre-push-gate.sh")
assert_contains "$out" 'codex-review' "push gate blocks without review"

cd - >/dev/null; rm -rf "$(dirname "$T")"
finish
