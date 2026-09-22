@AGENTS.md

# Claude-specific
- Small tasks (bug, UI tweak): no ritual. Do it, run the test, commit. Brainstorm → plan → review only when the user asks or the change crosses modules.
- Gruntwork (scoped edits, searches): `core:worker` skill ({% if backend == 'opencode' %}DeepSeek on opencode go{% else %}Haiku subagent `worker`{% endif %}); exit 3 → Sonnet subagent (`Agent` tool, `model: sonnet`). You run the tests, trimmed (`| tail -40`).
- Stuck: `core:rescue` skill ({% if backend == 'opencode' %}fresh DeepSeek session{% else %}Sonnet subagent `rescuer`{% endif %}); verify with `git diff` and the failing command before trusting "done".
- Review: pre-push runs `scripts/review.sh` on sensitive diffs only (auth, API, db, gates) and blocks; the night shift reviews the rest. When it blocks: `core:review` skill. Never bypass; the human can type `SKIP_REVIEW=1 git push` themselves.
- Docs: the night shift refreshes them; run the `doc-keeper` agent (mode diff) only when the user asks or a feature ships.
- Usage: subagents run on Haiku by default (`CLAUDE_CODE_SUBAGENT_MODEL`); `model: sonnet` only for the worker fallback and visual checks. Never Agent Teams.{% if backend == 'opencode' %} Do not enable the Codex plugin's review gate.{% endif %}
- Visual verification: a Sonnet subagent drives headless Chrome via the Playwright CLI (viewports 1440×900 and 390×844), reads the screenshots, then deletes them.
- Ponytail level lite: smallest change at the right level — colours, components and business rules are fixed at the source, never in the screen.
- End of a work block or before the quota runs out: `core:handoff` skill (always the qualified name); it prints a prompt to paste into the next session, any tool.
