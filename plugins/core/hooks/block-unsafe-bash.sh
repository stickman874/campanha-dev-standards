#!/usr/bin/env bash
# Fails open if jq is missing (cmd empty → allow); deliberate — a broken hook must not block all Bash.
# PreToolUse/Bash: deny gate bypasses, dotenv reads and destructive database commands.
cmd=$(jq -r '.tool_input.command // ""')
deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
# Gate bypasses, anchored to a real git/lefthook invocation in the same command segment (quotes, heredocs and commit messages do not match).
# Quoted args are stepped over as opaque blocks (so a --no-verify inside a commit message never matches) but the group can also
# stop right at a quote's opening mark, so a flag whose value itself starts with the target text (e.g. -c 'core.hooksPath=...') still matches.
seg="(^|[;&|(][[:space:]]*)(\\b(sudo|env|command|exec|then|do|time|nohup)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|'[^']*'|[^[:space:]]*)[[:space:]]+)*"
args='([^;&|"'"'"']|"[^"]*"|'"'"'[^'"'"']*'"'"')*'
printf '%s' "$cmd" | grep -Eiq -- "${seg}(git|lefthook|npx[[:space:]]+lefthook)[[:space:]]+${args}(--no-ve[a-z-]*|--no-gpg-sign)" \
  && deny "Git hooks are the quality gate. Never bypass them; fix what the hook reports."
# short no-verify: -n on git commit (not -m), including clusters like -an, but never a lone -m
printf '%s' "$cmd" | grep -Eq -- "${seg}git[[:space:]]+${args}commit${args}[[:space:]]-[a-z]*n[a-z]*([[:space:]]|\$)" \
  && deny "Git hooks are the quality gate. Never bypass them; fix what the hook reports."
printf '%s' "$cmd" | grep -Eiq -- "${seg}git[[:space:]]+${args}['\"]?core\\.hookspath" \
  && deny "Git hooks are the quality gate. Never bypass them; fix what the hook reports."
printf '%s' "$cmd" | grep -Eq -- "${seg}((export|declare[[:space:]]+-x)[[:space:]]+)?(SKIP_REVIEW=(\"1\"|'1'|1)|LEFTHOOK=(\"0\"|'0'|0)|LEFTHOOK_EXCLUDE=|OPENCODE_SH=)" \
  && deny "Skipping the review is the human's call, not yours. Tell the user why it blocked and the exact command they can type themselves."
# force pushes and pushes targeting a prod-named ref
printf '%s' "$cmd" | grep -Eq -- "${seg}git[[:space:]]+${args}push${args}(--force(-with-lease)?|[[:space:]]-f\\b|[[:space:]]\\+)" \
  && deny "Force pushes are never automated. Ask the human to run it themselves if it is truly needed."
printf '%s' "$cmd" | grep -Eq -- "${seg}git[[:space:]]+${args}push${args}([[:space:]]|:)prod([[:space:]]|\$)" \
  && deny "Pushes targeting a prod-named ref are never automated. Ask the human to run it themselves."
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
