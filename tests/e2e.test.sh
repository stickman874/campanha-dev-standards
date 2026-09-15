#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
export PATH="$HOME/.local/bin:$PATH"
command -v lefthook >/dev/null && command -v gitleaks >/dev/null || { echo "  skip e2e (lefthook or gitleaks missing; run install.sh)"; exit 0; }

R=$PWD; T=$(mktemp -d)/fixture; mkdir -p "$T"; cd "$T"; git init -q
printf '{"name":"fixture","scripts":{"test":"echo tests-ok"},"devDependencies":{}}\n' > package.json
bash "$R/plugins/core/scripts/adopt.sh" "$T" --tenant single >/dev/null
mkdir -p scripts && cp "$R"/plugins/core/templates/scripts/*.sh scripts/

# The fixture never runs `npm install`, so eslint isn't available and the
# `lint` pre-commit command (`npx eslint {staged_files}`) would fail on any
# staged .ts/.tsx regardless of content. Drop it here so the test exercises
# gitleaks and design-lint (the commands under test), not a missing eslint.
sed -i '/^    lint:/,/^      run:/d' lefthook.yml

git add -A && git -c user.name=t -c user.email=t@t commit -qm "chore: adopt" && echo "  ok  adopt commit passes pre-commit" || { echo "  FAIL adopt commit blocked"; FAILS=$((FAILS+1)); }


mkdir -p src && echo x > src/x.ts; git add -A
git -c user.name=t -c user.email=t@t commit -qm "code"
assert_exit 1 bash scripts/docs-check.sh HEAD~1

cd - >/dev/null; rm -rf "$(dirname "$T")"
finish
