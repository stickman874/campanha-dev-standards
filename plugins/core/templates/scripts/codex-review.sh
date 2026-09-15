#!/usr/bin/env bash
# pre-push: Codex adversarial review of the range being pushed. Blocks on VERDICT: block or when the verdict is missing.
# Model: sol/medium for routine diffs, astra/medium when the diff touches auth, payments, API handlers, migrations or the gates.
set -u
base=${1:-$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo origin/main)}
changed=$(git diff --name-only "$base...HEAD" 2>/dev/null) || { echo "codex-review: cannot diff $base...HEAD" >&2; exit 1; }
[ -n "$changed" ] || exit 0
command -v codex >/dev/null || { echo "codex-review: codex CLI not found (mise install; codex login)" >&2; exit 1; }
model=gpt-5.6-sol; effort=medium
printf '%s\n' "$changed" | grep -qiE 'auth|session|permission|payment|stripe|billing|src/app/api/|/actions/|server/|migrations|prisma/schema|lefthook|\.claude/|\.opencode/|scripts/(codex-review|docs-check)' && model=gpt-6-astra
model=${CODEX_REVIEW_MODEL:-$model}; effort=${CODEX_REVIEW_EFFORT:-$effort}
start=$(date +%s)
out=$(codex review --base "$base" -c "model=\"$model\"" -c "model_reasoning_effort=\"$effort\"" \
  "Adversarial review. Look for correctness bugs, security holes (authorization, data exposure, injection, secrets), data loss, broken edge cases, changed behaviour without a test. Ignore style. List findings as '[high|medium|low] file:line — what breaks — minimal fix'. End with exactly one line: 'VERDICT: approve' if nothing high, else 'VERDICT: block'." 2>&1)
rc=$?
echo "$out"
echo "codex-review: model=$model effort=$effort base=$base secs=$(( $(date +%s) - start ))"
[ $rc -eq 0 ] || { echo "codex-review: codex exited $rc" >&2; exit 1; }
printf '%s\n' "$out" | grep -q '^VERDICT: approve' && exit 0
echo "codex-review: blocked (fix the [high] findings, commit, push again)" >&2
exit 1
