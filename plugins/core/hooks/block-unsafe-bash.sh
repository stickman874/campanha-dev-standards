#!/usr/bin/env bash
# Fails open if jq is missing (cmd empty → allow); deliberate — a broken hook must not block all Bash.
# PreToolUse/Bash: deny gate bypasses and destructive database commands. Secrets are handled by the sandbox and permissions.deny.
cmd=$(jq -r '.tool_input.command // ""')
deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
printf '%s' "$cmd" | grep -Eq -- '--no-verify|--no-gpg-sign|core\.hooksPath|LEFTHOOK=0|LEFTHOOK_EXCLUDE' \
  && deny "Git hooks are the quality gate. Never bypass them; fix what the hook reports."
printf '%s' "$cmd" | grep -Eq 'prisma (db push|migrate reset)' \
  && deny "prisma db push / migrate reset are forbidden. Use 'prisma migrate dev --name <name>' and never reset a shared database."
printf '%s' "$cmd" | grep -Eq 'supabase db reset.*--linked' \
  && deny "supabase db reset --linked targets the remote project. Local reset only."
exit 0
