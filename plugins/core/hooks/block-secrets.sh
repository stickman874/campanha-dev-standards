#!/usr/bin/env bash
# Fails open if jq is missing (cmd empty → allow); deliberate — a broken hook must not block all Bash.
# PreToolUse/Bash hook: deny any command whose text contains a recognizable secret,
# so Claude can't echo a live credential into the terminal/transcript. The fix on a
# block is to pipe the secret from a shell var or file instead of pasting it inline.
# Patterns are chosen to be specific enough to avoid firing on ordinary commands.
cmd=$(jq -r '.tool_input.command // ""')

# name=VALUE regex pairs. Keep each anchored to a real credential shape.
patterns=(
  'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+'  # JWT (Supabase/Auth0/GCP service tokens)
  'sb_secret_[A-Za-z0-9_-]{8,}'                                  # Supabase secret key
  'AKIA[0-9A-Z]{16}'                                             # AWS access key id
  'ASIA[0-9A-Z]{16}'                                             # AWS temp access key id
  'gh[pousr]_[A-Za-z0-9]{30,}'                                   # GitHub token
  'github_pat_[A-Za-z0-9_]{30,}'                                 # GitHub fine-grained PAT
  'sk-(proj-)?[A-Za-z0-9_-]{20,}'                                # OpenAI / Anthropic-style key
  'sk_live_[A-Za-z0-9]{20,}'                                     # Stripe live secret
  'rk_live_[A-Za-z0-9]{20,}'                                     # Stripe restricted live
  'xox[baprs]-[A-Za-z0-9-]{10,}'                                 # Slack token
  'AIza[0-9A-Za-z_-]{35}'                                        # Google API key
  'glpat-[A-Za-z0-9_-]{20,}'                                     # GitLab PAT
  'https://hooks\.slack\.com/services/[A-Za-z0-9/]+'            # Slack webhook
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'                          # PEM private key block
)

for p in "${patterns[@]}"; do
  if printf '%s' "$cmd" | grep -Eq -e "$p"; then
    jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"This command contains what looks like a live secret pasted inline. Do not echo credentials into a shell command — put the value in a shell variable, a file, or an interactive prompt (e.g. stdin) and reference it, so it never lands in the terminal or transcript."}}'
    exit 0
  fi
done
exit 0
