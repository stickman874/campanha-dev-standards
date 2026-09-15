#!/usr/bin/env bash
# pre-push: code changed but docs/ and CHANGELOG did not → block. Fix: doc-keeper agent (Claude) or edit docs by hand.
# Ranges come from git's pre-push stdin (lefthook: use_stdin: true) or from an explicit <base> argument.
z=0000000000000000000000000000000000000000
ranges() {
  if [ -n "${1:-}" ]; then echo "$1 HEAD"; return; fi
  local lref lsha rref rsha any=
  if [ ! -t 0 ]; then while read -r lref lsha rref rsha; do
    [ "${lsha:-$z}" = "$z" ] && continue
    [ "${rsha:-$z}" = "$z" ] && rsha=$(git merge-base origin/HEAD "$lsha" 2>/dev/null || echo origin/main)
    echo "$rsha $lsha"; any=1
  done; fi
  [ -n "$any" ] || echo "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo origin/main) HEAD"
}
rc=0
while read -r from to; do
  changed=$(git diff --name-only "$from...$to" 2>/dev/null) || continue
  printf '%s\n' "$changed" | grep -qE '^(src/|app/|prisma/|supabase/|deploy/|Dockerfile|docker-compose|\.env\.example)' || continue
  printf '%s\n' "$changed" | grep -qE '^(docs/|CHANGELOG\.md)' && continue
  echo "docs-check: code changed ($from...$to) without docs/ or CHANGELOG.md. Run the doc-keeper agent (mode diff) or update the docs, then push again." >&2; rc=1
done < <(ranges "${1:-}")
exit $rc
