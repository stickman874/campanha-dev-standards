#!/usr/bin/env bash
# Fails open if jq is missing (cmd empty → allow); deliberate — a broken hook must not block all Bash.
# PreToolUse/Bash on `git push`: require codex-review + doc-keeper markers for HEAD.
# The actual `git push` triggers lefthook's own installed pre-push hook (which
# blocks on failure and whose output Claude sees), so this gate only checks
# markers — running lefthook here too would double the budget and risk the
# hook timeout.
cmd=$(jq -r '.tool_input.command // ""')
printf '%s' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_-])git( +-[^ ]+| +-C +[^ ]+)* +push([^A-Za-z0-9_-]|$)' || exit 0
printf '%s' "$cmd" | grep -Eq -- '--help|--dry-run|(^| )-n( |$)' && exit 0
deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
sha=$(git rev-parse HEAD 2>/dev/null) || exit 0
dir=$(git rev-parse --git-dir)/campanha

[ -f "$dir/reviewed-$sha" ] || deny "Push blocked: run the codex-review skill on the current diff first (it runs /codex:adversarial-review, you fix findings, it writes $dir/reviewed-$sha)."
[ -f "$dir/docs-$sha" ]     || deny "Push blocked: invoke the doc-keeper agent (mode push) to update docs/ and CHANGELOG for this change first (it writes $dir/docs-$sha)."
exit 0
