@AGENTS.md

# Claude-specific
- Method: superpowers (brainstorm → plan → approval → implement with subagents → verify).
- Gruntwork (scoped edits, searches): `core:worker` skill (DeepSeek); `DEEPSEEK_UNAVAILABLE` → Sonnet subagent (`Agent` tool, `model: sonnet`). You run the tests, trimmed (`| tail -40`).
- Before implementing a plan: use the `codex-review` skill on the plan.
- Before any push: run the `doc-keeper` agent (mode diff); the pre-push hook runs Codex review and the docs check and blocks on failure. One push per unit of work, not per commit.
- Visual verification: a Sonnet subagent drives headed Chrome via Playwright (viewports 1440×900 and 390×844), then deletes screenshots.
- Ponytail level lite: smallest change at the right level — colours, components and business rules are fixed at the source, never in the screen.
- End of a work block: `core:handoff` skill (always the qualified name; a bare `handoff` may resolve to another plugin's user-only skill).
- When stuck on a task: `/codex:rescue`, then verify with `git diff` before trusting its "done".
