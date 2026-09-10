#!/usr/bin/env bash
# Fails open if jq is missing (cmd empty → allow); deliberate — a broken hook must not block all Bash.
# PreToolUse/Bash: deny commands that bypass gates or touch secrets/production data.
cmd=$(jq -r '.tool_input.command // ""')
deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }

printf '%s' "$cmd" | grep -Eq -- '--no-verify|--no-gpg-sign' \
  && deny "Git hooks are the quality gate. Never bypass them with --no-verify; fix what the hook reports."

# any .env file except .env.example — strip .env.example occurrences first so
# they can't shield a real .env reference elsewhere in the same command.
rest=${cmd//.env.example/}
if printf '%s' "$rest" | grep -Eq '(^|[^A-Za-z0-9_./-])\.env(\.[A-Za-z0-9_-]+)?($|[^A-Za-z0-9_.-])'; then
  deny "Reading .env files is blocked: secrets must never enter the transcript. Use .env.example to see variable names."
fi

printf '%s' "$cmd" | grep -Eq 'prisma (db push|migrate reset)' \
  && deny "prisma db push / migrate reset are forbidden. Use 'prisma migrate dev --name <name>' and never reset a shared database."

printf '%s' "$cmd" | grep -Eq 'supabase db reset.*--linked' \
  && deny "supabase db reset --linked targets the remote project. Local reset only."

exit 0
