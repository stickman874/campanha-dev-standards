---
description: Weekly documentation drift check - compares docs/dev and docs/product with the code and recent specs, fixes on a branch, and reports a PR-ready summary.
---

# /docs-consolidate

1. Invoke the `doc-keeper` agent in **mode consolidate**.
2. It works on branch `docs/consolidate-<YYYY-MM-DD>` and never pushes.
3. Show the user the summary (drift found, files changed, NEEDS DECISION items, undeclared exceptions in AGENTS.md).
4. Ask whether to push the branch and open a PR (`gh pr create --fill`). Do nothing else without confirmation.

Schedule: run weekly (Claude `/schedule`, or the existing cron pattern). Not automated by this plugin.
