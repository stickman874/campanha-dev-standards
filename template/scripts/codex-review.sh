#!/usr/bin/env bash
# pre-push: Codex adversarial review of every range being pushed. Blocks on VERDICT: block or a missing verdict.
# Model: sol/medium for routine diffs, astra/medium when the diff touches auth, payments, API handlers, migrations or the gates.
# Ranges come from git's pre-push stdin (lefthook: use_stdin: true) or from an explicit <base> argument.
set -u
z=0000000000000000000000000000000000000000
empty=4b825dc642cb6eb9a060e54bf8d69288fbee4904   # git's empty tree: base for a first push to an empty remote
ranges() {   # prints "from to" lines; trees are compared directly, so rollbacks (to = ancestor of from) are reviewed too
  if [ -n "${1:-}" ]; then echo "$1 HEAD"; return; fi
  local lref lsha rref rsha seen=
  if [ ! -t 0 ]; then while read -r lref lsha rref rsha; do
    seen=1
    [ "${lsha:-$z}" = "$z" ] && continue                     # branch deletion: nothing to review
    [ "${rsha:-$z}" = "$z" ] && rsha=$(git merge-base origin/HEAD "$lsha" 2>/dev/null || git merge-base origin/main "$lsha" 2>/dev/null || echo "$empty")   # new remote branch
    echo "$rsha $lsha"
  done; fi
  [ -n "$seen" ] || echo "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo origin/main) HEAD"
}
command -v codex >/dev/null || { echo "codex-review: codex CLI not found (mise install; codex login)" >&2; exit 1; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
rc_all=0
while read -r from to; do
  changed=$(git diff --name-only "$from" "$to" 2>/dev/null) || { echo "codex-review: cannot diff $from $to" >&2; exit 1; }
  [ -n "$changed" ] || continue
  model=gpt-5.6-sol; effort=medium
  printf '%s\n' "$changed" | grep -qiE 'auth|session|permission|payment|stripe|billing|src/app/api/|/actions/|server/|migrations|prisma/schema|lefthook|\.claude/|\.opencode/|scripts/(codex-review|docs-check)' && model=gpt-6-astra
  model=${CODEX_REVIEW_MODEL:-$model}; effort=${CODEX_REVIEW_EFFORT:-$effort}
  start=$(date +%s); : > "$tmp"
  # codex review --base rejects a custom prompt, so use exec in a read-only sandbox and let Codex run the diff itself
  out=$(codex exec -s read-only --ephemeral --skip-git-repo-check -m "$model" -c model_reasoning_effort="\"$effort\"" -o "$tmp" \
    "Adversarial code review of the changes between commits $from and $to in this repository (run: git diff $from $to — trees compared directly; read files for context). Look for correctness bugs, security holes (authorization, data exposure, injection, secrets), data loss, broken edge cases, changed behaviour without a test. Ignore style. List findings as '[high|medium|low] file:line - what breaks - minimal fix'. End your final message with exactly one line: 'VERDICT: approve' if nothing high, else 'VERDICT: block'." 2>&1)
  rc=$?
  echo "$out"
  echo "codex-review: model=$model effort=$effort range=$from..$to secs=$(( $(date +%s) - start ))"
  [ $rc -eq 0 ] || { echo "codex-review: codex exited $rc" >&2; exit 1; }
  # only the final message counts, and only its last non-empty line (quoted text or tool output cannot approve)
  [ "$(grep -v '^[[:space:]]*$' "$tmp" | tail -1)" = "VERDICT: approve" ] || { echo "codex-review: blocked for $from..$to (fix the [high] findings, commit, push again)" >&2; rc_all=1; }
done < <(ranges "${1:-}")
exit $rc_all
