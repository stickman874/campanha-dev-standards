#!/usr/bin/env bash
# Fails open if jq is missing (cmd empty → allow); deliberate — a broken hook must not block all Bash.
# PreToolUse/Bash on `git push`: require codex-review + doc-keeper markers for HEAD, then run lefthook pre-push.
cmd=$(jq -r '.tool_input.command // ""')
printf '%s' "$cmd" | grep -Eq '(^|[;&|] *)git push( |$)' || exit 0
deny() { jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
sha=$(git rev-parse HEAD 2>/dev/null) || exit 0
dir=$(git rev-parse --git-dir)/campanha

[ -f "$dir/reviewed-$sha" ] || deny "Push blocked: run the codex-review skill on the current diff first (it runs /codex:adversarial-review, you fix findings, it writes $dir/reviewed-$sha)."
[ -f "$dir/docs-$sha" ]     || deny "Push blocked: invoke the doc-keeper agent (mode push) to update docs/ and CHANGELOG for this change first (it writes $dir/docs-$sha)."

if [ -f lefthook.yml ] && command -v lefthook >/dev/null; then
  out=$(lefthook run pre-push --force --colors off 2>&1) || deny "Push blocked: lefthook pre-push failed. Fix the reported problems, never bypass. Output:
$out"
fi
exit 0
