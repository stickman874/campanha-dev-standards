#!/usr/bin/env bash
# Fails open if jq is missing (cmd empty → allow); deliberate — a broken hook must not block all Bash.
# PreToolUse/Bash: deny gate bypasses, dotenv reads and destructive database commands.
cmd=$(jq -r '.tool_input.command // ""')
deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
# Gate bypasses, anchored to a real git/lefthook invocation in the same command segment (quotes, heredocs and commit messages do not match).
seg='(^|[;&|(][[:space:]]*|\bsudo[[:space:]]+|\benv[[:space:]]+)([A-Z_]+=[^[:space:]]*[[:space:]]+)*'
printf '%s' "$cmd" | grep -Eq -- "${seg}(git|lefthook|npx[[:space:]]+lefthook)[[:space:]][^;&|\"']*(--no-verify|--no-gpg-sign|core\.hooksPath)" \
  && deny "Git hooks are the quality gate. Never bypass them; fix what the hook reports."
printf '%s' "$cmd" | grep -Eq -- "${seg}(export[[:space:]]+)?(SKIP_REVIEW=1|LEFTHOOK=0|LEFTHOOK_EXCLUDE=)" \
  && deny "Skipping the review is the human's call, not yours. Tell the user why it blocked and the exact command they can type themselves."
# dotenv files read by a shell command (not merely mentioned, e.g. in a commit message), quoted or not. Belt and braces
# for repos whose .claude/settings.json predates the sandbox; .env.example is allowed.
rest=${cmd//.env.example/}
q='"'"'"   # a double quote and a single quote
readers='(^|[;&|(]|\bsudo|\bxargs)[[:space:]]*(cat|less|more|head|tail|bat|source|\.|grep|rg|sed|awk|cut|cp|mv|python3?|node|export \$\(cat)[^;&|]*'
printf '%s' "$rest" | grep -Eq -- "${readers}[[:space:]/${q}]\\.env(\\.[A-Za-z0-9_-]+)?([[:space:]${q}]|\$|[;&|)])" \
  && deny "Reading dotenv files is blocked: secrets must never enter the transcript. Use .env.example for variable names."
printf '%s' "$cmd" | grep -Eq 'prisma (db push|migrate reset)' \
  && deny "prisma db push / migrate reset are forbidden. Use 'prisma migrate dev --name <name>' and never reset a shared database."
printf '%s' "$cmd" | grep -Eq 'supabase db reset.*--linked' \
  && deny "supabase db reset --linked targets the remote project. Local reset only."
exit 0
