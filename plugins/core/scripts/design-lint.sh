#!/usr/bin/env bash
# Fail on hardcoded colours and Tailwind arbitrary values outside the token files.
# ponytail: grep-based; upgrade to an eslint rule if false positives appear.
files=("$@")
# Explicit file list (lefthook staged_files) -> only check NEW lines (diff-aware,
# so touching a file for an unrelated reason, e.g. one import path, doesn't
# resurface pre-existing violations elsewhere in that file). No args -> full
# repo audit scan of whole file contents.
mode=diff; [ ${#files[@]} -eq 0 ] && { mode=full; mapfile -t files < <(git ls-files '*.tsx' '*.jsx' '*.css'); }
rc=0
pattern='#[0-9a-fA-F]{3,8}\b|\b(text|bg|w|h|p[xytblr]?|m[xytblr]?|gap|rounded|border|top|right|bottom|left|min-w|max-w|min-h|max-h|leading|tracking|size|inset)-\[[^]]+\]'
for f in "${files[@]}"; do
  case "$f" in *globals.css|*DESIGN.md|*tokens*|*.test.*) continue;; esac
  # src/components/ui/ is the canonical primitives library (shadcn/kibo-ui
  # vendor components + hand-built primitives) — the token *source*, not a
  # consumer; one-off pixel affordances here are expected, same as globals.css.
  case "$f" in */components/ui/*) continue;; esac
  [ -f "$f" ] || continue
  # Value-bearing utilities only; variant prefixes like data-[state=...]: and
  # supports-[...]: are intentionally allowed (they gate behavior, not tokens).
  # A bracket value that references a CSS custom property (var(--...), or a
  # bare --foo custom-property expression) is a token reference, not a
  # hardcoded value — exclude those from the match.
  if [ "$mode" = diff ]; then
    hits=$(git diff --cached -U0 -- "$f" | grep -E '^\+[^+]' | sed 's/^\+//' \
      | grep -nE "$pattern" | grep -vE '^[0-9]+:\s*(//|/\*)' | grep -vE '\[[^]]*(var\(--|--[a-zA-Z])')
  else
    hits=$(grep -nE "$pattern" "$f" | grep -vE '^[0-9]+:\s*(//|/\*)' | grep -vE '\[[^]]*(var\(--|--[a-zA-Z])')
  fi
  [ -n "$hits" ] && { echo "design-lint: $f"; echo "$hits"; rc=1; }
done
[ $rc -ne 0 ] && echo "Use tokens from globals.css / DESIGN.md and canonical components. Add missing tokens globally, never inline." >&2
exit $rc
