@AGENTS.md

# Claude-specific
- Process: the superpowers skills for brainstorm → spec → plan. Execution does not use `subagent-driven-development` or `executing-plans`: run the plan in batches as `## Parallel work` says, with `sonnet` workers and no per-task spec or quality reviewer. A superpowers skill that says otherwise loses to this line. Small tasks (bug, UI tweak): no ritual — do it, run the test, commit. Brainstorm → spec → plan only when the user asks or the change crosses modules. This overrides superpowers' "invoke a skill on a 1% chance" rule.
- Delegation: built-in `general-purpose` subagents with an explicit `model` — `sonnet` for scoped edits, searches, getting unstuck and visual checks (Haiku only after Haiku 5.5 ships). You run the tests; you commit.
- Stuck: `systematic-debugging` first; then a fresh `general-purpose` subagent on `sonnet` with the problem, the failing command and its output. Verify with `git diff` and that command before trusting "done". `/codex:rescue` is the user's manual escalation.
- Spec and plan review (replaces superpowers' own spec/plan reviewer subagent): `Agent` with `subagent_type: "codex:codex-rescue"` and the prompt `--wait. Read-only, do not edit. Adversarially review the spec/plan at <path>: assumptions, alternatives, failure modes, migration gaps.` Show its output as-is and check `git status` is unchanged. Empty result or error → a `general-purpose` subagent on `sonnet` with the same prompt; say so in one line. Decide with the user; one line per rejected finding under `## Review notes`.
- Push blocked: never bypass; the human can type `SKIP_REVIEW=1 git push` themselves.
- Docs: the night shift refreshes them; run the `doc-keeper` agent (mode diff) only when the user asks or a feature ships.
- Usage: never Agent Teams. Do not enable the Codex plugin's review gate.
- Visual verification: a `sonnet` subagent drives headless Chrome via the Playwright CLI (viewports 1920×1080 and 402×874), reads the screenshots, then deletes them.
- Ponytail level lite: smallest change at the right level — colours, components and business rules are fixed at the source, never in the screen.
