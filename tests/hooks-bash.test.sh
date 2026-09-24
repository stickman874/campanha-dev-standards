#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
H=plugins/core/hooks
run() { jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$H/$1"; }
deny() { assert_contains "$(run "$1" "$2")" '"deny"' "$1 denies: $2"; }
allow() { assert_eq "" "$(run "$1" "$2")" "$1 allows: $2"; }

# build a token-shaped string at runtime so no literal secret shape lives in the repo
fake_gh="ghp_$(printf 'a%.0s' $(seq 1 36))"
deny  block-secrets.sh "echo $fake_gh"
allow block-secrets.sh 'git status'

deny  block-unsafe-bash.sh 'cat .env'
deny  block-unsafe-bash.sh 'cd app && cat .env.local'
deny  block-unsafe-bash.sh 'source .env.production'
deny  block-unsafe-bash.sh 'cat deploy/.env.secrets'
deny  block-unsafe-bash.sh 'export $(cat .env | xargs)'
deny  block-unsafe-bash.sh 'cat "deploy/.env.secrets"'
deny  block-unsafe-bash.sh "cat '.env.local'"
allow block-unsafe-bash.sh 'cat .env.example'
allow block-unsafe-bash.sh 'cat deploy/.env.example'
allow block-unsafe-bash.sh 'cat src/env.ts'
allow block-unsafe-bash.sh 'cat .envrc'
allow block-unsafe-bash.sh 'echo "see docs/.env docs"'
allow block-unsafe-bash.sh 'git commit -m "fix: use .env for config"'
deny  block-unsafe-bash.sh 'git commit -m x --no-verify'
deny  block-unsafe-bash.sh 'git push --no-verify'
deny  block-unsafe-bash.sh 'cd app && git push origin main --no-verify'
deny  block-unsafe-bash.sh 'git -c core.hooksPath=/dev/null push'
deny  block-unsafe-bash.sh 'git config core.hooksPath /dev/null'
deny  block-unsafe-bash.sh 'LEFTHOOK=0 git push'
deny  block-unsafe-bash.sh 'SKIP_REVIEW=1 git push'
deny  block-unsafe-bash.sh 'cd app && SKIP_REVIEW=1 git push origin main'
deny  block-unsafe-bash.sh 'export SKIP_REVIEW=1'
deny  block-unsafe-bash.sh 'export LEFTHOOK=0; git push'
deny  block-unsafe-bash.sh 'LEFTHOOK_EXCLUDE=review git push'
deny  block-unsafe-bash.sh 'OPENCODE_SH=./x.sh git push'
deny  block-unsafe-bash.sh 'env SKIP_REVIEW=1 git push'
deny  block-unsafe-bash.sh 'SKIP_REVIEW="1" git push'
deny  block-unsafe-bash.sh "SKIP_REVIEW='1' git push"
deny  block-unsafe-bash.sh 'git push "origin" --no-verify'
deny  block-unsafe-bash.sh "git push origin 'main' --no-verify"
deny  block-unsafe-bash.sh "git -c 'core.hooksPath=/dev/null' push"
deny  block-unsafe-bash.sh 'command git push --no-verify'
deny  block-unsafe-bash.sh 'exec git push --no-verify'
deny  block-unsafe-bash.sh 'if true; then git push --no-verify; fi'
deny  block-unsafe-bash.sh 'x=1 SKIP_REVIEW=1 git push'
deny  block-unsafe-bash.sh 'declare -x SKIP_REVIEW=1'
allow block-unsafe-bash.sh 'git commit -m "docs: explain why --no-verify is denied"'
allow block-unsafe-bash.sh 'echo "humans may run SKIP_REVIEW=1 git push"'
allow block-unsafe-bash.sh 'grep -rn "no-verify" plugins'
allow block-unsafe-bash.sh 'git push origin main'
allow block-unsafe-bash.sh 'git commit -m x'
deny  block-unsafe-bash.sh 'npx prisma db push'
deny  block-unsafe-bash.sh 'supabase db reset --linked'
deny  block-unsafe-bash.sh 'npx prisma migrate reset'
allow block-unsafe-bash.sh 'npx prisma migrate dev --name add_x'
allow block-unsafe-bash.sh 'supabase db reset'
finish
