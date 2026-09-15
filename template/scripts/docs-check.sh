#!/usr/bin/env bash
# pre-push: code changed but docs/ and CHANGELOG did not → block. Fix: doc-keeper agent (Claude) or edit docs by hand.
base=${1:-$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo origin/main)}
changed=$(git diff --name-only "$base...HEAD" 2>/dev/null) || exit 0
printf '%s\n' "$changed" | grep -qE '^(src/|app/|prisma/|supabase/|deploy/|Dockerfile|docker-compose|\.env\.example)' || exit 0
printf '%s\n' "$changed" | grep -qE '^(docs/|CHANGELOG\.md)' && exit 0
echo "docs-check: code changed ($base...HEAD) without docs/ or CHANGELOG.md. Run the doc-keeper agent (mode diff) or update the docs, then push again." >&2
exit 1
