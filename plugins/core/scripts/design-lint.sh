#!/usr/bin/env bash
# Fail on hardcoded colours and Tailwind arbitrary values outside the token files.
# ponytail: grep-based; upgrade to an eslint rule if false positives appear.
files=("$@"); [ ${#files[@]} -eq 0 ] && mapfile -t files < <(git ls-files '*.tsx' '*.jsx' '*.css')
rc=0
for f in "${files[@]}"; do
  case "$f" in *globals.css|*DESIGN.md|*tokens*|*.test.*) continue;; esac
  [ -f "$f" ] || continue
  # Value-bearing utilities only; variant prefixes like data-[state=...]: and
  # supports-[...]: are intentionally allowed (they gate behavior, not tokens).
  hits=$(grep -nE '#[0-9a-fA-F]{3,8}\b|\b(text|bg|w|h|p[xytblr]?|m[xytblr]?|gap|rounded|border|top|right|bottom|left|min-w|max-w|min-h|max-h|leading|tracking|size|inset)-\[[^]]+\]' "$f" | grep -vE '^[0-9]+:\s*(//|/\*)')
  [ -n "$hits" ] && { echo "design-lint: $f"; echo "$hits"; rc=1; }
done
[ $rc -ne 0 ] && echo "Use tokens from globals.css / DESIGN.md and canonical components. Add missing tokens globally, never inline." >&2
exit $rc
