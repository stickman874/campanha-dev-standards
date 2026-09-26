---
description: Bring this repository up to the campanha-dev-standards (templates, gates, docs tree), then migrate existing documentation with doc-keeper.
---

# /adopt

1. Copier is not in the repo yet on a first adopt: `mise use -g pipx:copier` (or prefix the command with `uvx`). Then `copier copy --trust gh:stickman874/campanha-dev-standards .` (answer project name and tenant; explain tenant in one sentence if asked). Existing repo already adopted: `copier update --trust` instead. Already adopted on a version before 0.5.0: follow "Upgrading to 0.5.0" in the campanha-dev-standards README instead.
2. Existing repo: copier never overwrites `.claude/settings.json`; merge `"sandbox": { "enabled": true, "autoAllowBashIfSandboxed": true }` and the `enabledPlugins` block from the template by hand (core, superpowers, typescript-lsp, codex; drop security-guidance, commit-commands, playwright and impeccable if present). Read the output. If `mise` is missing: `curl https://mise.run | sh`, then rerun step 1's task: `mise install && lefthook install`. `scripts/review.sh`, `scripts/opencode.sh`, `opencode.json` and `.opencode/agents/{orchestrator,worker,rescuer,reviewer,docs}.md` come from the template; each dev runs `opencode auth login` once for opencode go (push review) and once for OpenAI (the opencode orchestrator), and `codex login` for the Claude spec review.
3. If the repo already had documentation (README beyond a stub, `docs/*` outside `dev|product`, root PRD/RESUME/handoff files, `.planning/`, an oversized CLAUDE.md): invoke the `doc-keeper` agent in **mode bootstrap**. It moves content into the standard tree, never deletes sources, and writes `docs/dev/decisions/0001-adopt-report.md` listing what went where and what needs a decision.
4. Conflicts between old instructions and the standard: security/gate rules → standard wins, list it; conventions → standard wins unless the user confirms an exception under `## Exceptions` in AGENTS.md; more specific rules → keep in AGENTS.md or `.claude/rules/`.
5. Design lint: follow `docs/dev/how-to/design-lint.md` (eslint plugin) if the project uses Tailwind.
6. No tests? Add the smallest vitest smoke test so pre-push can pass. Then `npx tsc --noEmit`, `npm test -- --run`, `lefthook run pre-push` (review runs only if the adopt diff touches sensitive paths). Report failures; do not bypass.
7. Commit on branch `chore/adopt-standards`.
8. Server: add the repo's checkout path to `/etc/campanha/repos` on box-one (see `deploy/nightly/README.md`) so the night shift covers it.
