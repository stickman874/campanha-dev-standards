@AGENTS.md

# Claude-specific
- Method: superpowers (brainstorm → plan → approval → implement with subagents → verify).
- Gruntwork (scoped edits, searches): `core:worker` skill (DeepSeek); `DEEPSEEK_UNAVAILABLE` → Sonnet subagent (`Agent` tool, `model: sonnet`). You run the tests, trimmed (`| tail -40`).
- Before implementing a plan: use the `codex-review` skill on the plan.
- Before any push: run the `doc-keeper` agent (mode diff); the pre-push hook runs the docs check and, on sensitive diffs (auth, API, db, gates), semgrep and the Codex review, and blocks on failure. Routine diffs: `bash scripts/codex-review.sh <base>` when you want a second opinion. One push per unit of work, not per commit.
- Usage: subagents run on Haiku by default (`CLAUDE_CODE_SUBAGENT_MODEL`); pass `model: sonnet` only for the worker fallback and visual checks. Never Agent Teams (~7x tokens). Do not enable the Codex plugin's `--enable-review-gate` stop hook (review loops burn both quotas).
- Visual verification: a Sonnet subagent drives headless Chrome via the Playwright CLI (viewports 1440×900 and 390×844), reads the screenshots, then deletes them.
- Ponytail level lite: smallest change at the right level — colours, components and business rules are fixed at the source, never in the screen.
- End of a work block: `core:handoff` skill (always the qualified name; a bare `handoff` may resolve to another plugin's user-only skill).
- When stuck on a task: `/codex:rescue`, then verify with `git diff` before trusting its "done".
