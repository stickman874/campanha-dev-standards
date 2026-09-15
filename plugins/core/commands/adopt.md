---
description: Bring this repository up to the campanha-dev-standards (templates, gates, docs tree), then migrate existing documentation with doc-keeper.
---

# /adopt

1. `copier copy --trust gh:stickman874/campanha-dev-standards .` (answer project name and tenant; explain tenant in one sentence if asked). Existing repo already adopted: `copier update --trust` instead.
2. Read the output. If `mise` is missing: `curl https://mise.run | sh`, then rerun step 1's task: `mise install && lefthook install`.
3. If the repo already had documentation (README beyond a stub, `docs/*` outside `dev|product`, root PRD/RESUME/handoff files, `.planning/`, an oversized CLAUDE.md): invoke the `doc-keeper` agent in **mode bootstrap**. It moves content into the standard tree, never deletes sources, and writes `docs/dev/decisions/0001-adopt-report.md` listing what went where and what needs a decision.
4. Conflicts between old instructions and the standard: security/gate rules → standard wins, list it; conventions → standard wins unless the user confirms an exception under `## Exceptions` in AGENTS.md; more specific rules → keep in AGENTS.md or `.claude/rules/`.
5. Design lint: follow `docs/dev/how-to/design-lint.md` (eslint plugin) if the project uses Tailwind.
6. No tests? Add the smallest vitest smoke test so pre-push can pass. Then `npx tsc --noEmit`, `npm test -- --run`, `lefthook run pre-push` (it will call Codex; expect a review). Report failures; do not bypass.
7. Commit on branch `chore/adopt-standards`. End with the `core:handoff` skill.
