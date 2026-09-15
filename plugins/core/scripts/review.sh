#!/usr/bin/env bash
# Adversarial review of pushed ranges by the project's read-only `reviewer` opencode agent (DeepSeek on opencode go).
#   review.sh                  ranges from git's pre-push stdin (lefthook use_stdin) — only ranges touching sensitive paths; routine ones are skipped
#   review.sh <from> [<to>]    explicit range (to = HEAD) — always reviewed
#   review.sh --all            stdin ranges, every range reviewed (night shift)
# Blocks (exit 1) on verdict block, any high finding, no valid JSON, or reviewer unavailable. Never approves on failure.
# SKIP_REVIEW=1 git push (typed by a human, never by an agent): skips and logs the range to docs/dev/reviews/skipped.log; the night shift reviews it.
set -u
here=$(cd "$(dirname "$0")" && pwd)
runner=${OPENCODE_SH:-}
[ -n "$runner" ] || for c in "$here/opencode.sh" "${CLAUDE_PLUGIN_ROOT:-}/scripts/opencode.sh" ~/.claude/plugins/cache/*/campanha-dev-standards/*/plugins/core/scripts/opencode.sh ~/.claude/plugins/marketplaces/campanha-dev-standards/plugins/core/scripts/opencode.sh; do [ -f "$c" ] && { runner=$c; break; }; done
z=0000000000000000000000000000000000000000; empty=4b825dc642cb6eb9a060e54bf8d69288fbee4904
SENSITIVE='auth|session|permission|payment|stripe|billing|src/app/api/|/actions/|server/|migrations|prisma/schema|lefthook|\.claude/|\.opencode/|^scripts/'
all=; case ${1:-} in --all) all=1; shift;; esac
explicit=${1:+1}
ranges() {   # "from to" lines; trees compared directly, so rollbacks are reviewed too
  if [ -n "${1:-}" ]; then echo "$1 ${2:-HEAD}"; return; fi
  local lref lsha rref rsha seen=
  if [ ! -t 0 ]; then while read -r lref lsha rref rsha; do
    seen=1; [ "${lsha:-$z}" = "$z" ] && continue                                 # branch deletion
    [ "${rsha:-$z}" = "$z" ] && rsha=$(git merge-base origin/HEAD "$lsha" 2>/dev/null || git merge-base origin/main "$lsha" 2>/dev/null || echo "$empty")
    echo "$rsha $lsha"
  done; fi
  [ -n "$seen" ] || echo "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo origin/main) HEAD"
}
if [ "${SKIP_REVIEW:-}" = 1 ]; then
  mkdir -p docs/dev/reviews
  ts=$(date -u +%FT%TZ); who=$(git config user.name 2>/dev/null || echo '?')
  ranges "$@" | while read -r from to; do printf '%s %s %s %s\n' "$ts" "$who" "$from" "$to"; done >> docs/dev/reviews/skipped.log
  echo "review: skipped by SKIP_REVIEW=1 (logged in docs/dev/reviews/skipped.log; the night shift reviews it)"; exit 0
fi
rc=0
while read -r from to; do
  changed=$(git diff --name-only "$from" "$to" -- 2>/dev/null) || { echo "review: cannot diff $from $to" >&2; exit 1; }
  [ -n "$changed" ] || continue
  if [ -z "$explicit$all" ] && ! printf '%s\n' "$changed" | grep -qiE "$SENSITIVE"; then
    echo "review: routine diff $from..$to, skipped (the night shift reviews it; bash scripts/review.sh $from reviews now)"; continue; fi
  [ -f "$runner" ] || { echo "review: opencode.sh not found (install the core plugin or set OPENCODE_SH)" >&2; exit 1; }
  start=$(date +%s)
  full=$(git diff "$from" "$to" --)
  size=$(printf '%s' "$full" | wc -c)
  body=$(printf '%s' "$full" | head -c 200000)
  note=
  if [ "$size" -gt 200000 ]; then
    note=$'\n'"(diff truncated at 200000 of $size bytes; treat this range as NOT fully reviewed and return verdict block unless you can read the listed files with your tools)"
    echo "review: diff truncated ($size bytes) for $from..$to" >&2
  fi
  out=$(OPENCODE_TIMEOUT=${REVIEW_TIMEOUT:-300} bash "$runner" "$PWD" reviewer <<EOF
Adversarial code review of the change between commits $from and $to in this repository.
Files changed:
$changed
Attack surface: authorization and tenant isolation, exposure or logging of personal data, injection (SQL, shell, HTML), secrets, input validation at API boundaries, data loss or irreversible migrations, broken edge cases, behaviour changed without a test.
Finding bar: only what would break, leak or be exploitable; ignore style. Each finding names the file and line you actually read, what breaks, and the minimal fix. Read surrounding code with your tools before deciding; never invent lines.
Output: one JSON object and nothing else, no code fences:
{"verdict":"approve"|"block","findings":[{"severity":"high"|"medium"|"low","file":"path","line":123,"what":"...","fix":"..."}]}
Verdict is block if any finding is high.
Diff:
$body$note
EOF
  ); code=$?
  echo "review: range=$from..$to secs=$(( $(date +%s) - start ))"
  [ "$code" -eq 0 ] || { echo "$out"; echo "review: reviewer unavailable, push blocked. Fix the cause, or force it yourself: SKIP_REVIEW=1 git push" >&2; rc=1; continue; }
  json=$(printf '%s\n' "$out" | tr -d '\r' | sed '/^```/d' | jq -c . 2>/dev/null | head -1)
  [ -n "$json" ] || json=$(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^[^{]*\({.*}\)[^}]*$/\1/p; /^{/p' | head -1 | jq -c . 2>/dev/null)   # ponytail: the JSON object on the first line that holds one, prose around it ignored
  [ "$(printf '%s\n' "$json" | wc -l)" -eq 1 ] || json=
  [ -n "$json" ] || { echo "$out"; echo "review: no valid JSON verdict, blocked" >&2; rc=1; continue; }
  printf '%s' "$json" | jq -r '.findings[]? | "[\(.severity)] \(.file):\(.line) - \(.what) - \(.fix)"'
  verdict=$(printf '%s' "$json" | jq -r '.verdict'); high=$(printf '%s' "$json" | jq '[.findings[]? | select(.severity=="high")] | length')
  [ "$verdict" = approve ] && [ "$high" -eq 0 ] || { echo "review: blocked for $from..$to (verdict=$verdict, high findings=$high). Fix, commit, push again." >&2; rc=1; }
done < <(ranges "$@")
exit $rc
