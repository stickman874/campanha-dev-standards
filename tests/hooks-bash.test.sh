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

deny  block-unsafe-bash.sh 'git commit -m x --no-verify'
deny  block-unsafe-bash.sh 'git push --no-verify'
allow block-unsafe-bash.sh 'cat .env'                       # native deny rules + sandbox own this now
allow block-unsafe-bash.sh 'git commit -m "fix: use .env for config"'
deny  block-unsafe-bash.sh 'git -c core.hooksPath=/dev/null push'
deny  block-unsafe-bash.sh 'git config core.hooksPath /dev/null'
deny  block-unsafe-bash.sh 'LEFTHOOK=0 git push'
deny  block-unsafe-bash.sh 'git push --no-verify'
deny  block-unsafe-bash.sh 'npx prisma db push'
deny  block-unsafe-bash.sh 'supabase db reset --linked'
deny  block-unsafe-bash.sh 'npx prisma migrate reset'
allow block-unsafe-bash.sh 'npx prisma migrate dev --name add_x'
allow block-unsafe-bash.sh 'supabase db reset'
allow block-unsafe-bash.sh 'git push origin main'
finish
