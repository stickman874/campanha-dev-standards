---
description: Bring this repository up to the campanha-dev-standards (templates, gates, docs tree), then migrate existing documentation with doc-keeper.
---

# /adopt

1. Copier is not in the repo yet on a first adopt: `mise use -g pipx:copier` (or prefix the command with `uvx`). Then `copier copy --trust gh:stickman874/campanha-dev-standards .` (answer project name, tenant and backend; explain tenant or backend in one sentence if asked — `claude` = Claude Code only, no opencode go, no Codex; `codex` = Claude orchestrates, gpt-6-sol on the Codex login does worker, rescue and review). Existing repo already adopted: `copier update --trust` instead.
2. Existing repo: copier never overwrites `.claude/settings.json`; merge `"sandbox": { "enabled": true, "autoAllowBashIfSandboxed": true }` and the `security-guidance`/`commit-commands`/`typescript-lsp` plugin entries from the template by hand. Read the output. If `mise` is missing: `curl https://mise.run | sh`, then rerun step 1's task: `mise install && lefthook install`. `scripts/review.sh` and the agents come from the template: `.opencode/agents/{worker,reviewer,docs}.md` (`opencode auth login` once per dev) or, on backend `claude`, `.claude/agents/{worker,rescuer,reviewer,docs}.md` (nothing to log into beyond Claude Code); on backend `codex` the same files, plus `codex login` once per dev and, on Windows, `[windows] sandbox = "unelevated"` in `~/.codex/config.toml`.
3. If the repo already had documentation (README beyond a stub, `docs/*` outside `dev|product`, root PRD/RESUME/handoff files, `.planning/`, an oversized CLAUDE.md): invoke the `doc-keeper` agent in **mode bootstrap**. It moves content into the standard tree, never deletes sources, and writes `docs/dev/decisions/0001-adopt-report.md` listing what went where and what needs a decision.
4. Conflicts between old instructions and the standard: security/gate rules → standard wins, list it; conventions → standard wins unless the user confirms an exception under `## Exceptions` in AGENTS.md; more specific rules → keep in AGENTS.md or `.claude/rules/`.
5. Design lint: follow `docs/dev/how-to/design-lint.md` (eslint plugin) if the project uses Tailwind.
6. No tests? Add the smallest vitest smoke test so pre-push can pass. Then `npx tsc --noEmit`, `npm test -- --run`, `lefthook run pre-push` (review runs only if the adopt diff touches sensitive paths). Report failures; do not bypass.
7. Commit on branch `chore/adopt-standards`. End with the `core:handoff` skill.
8. Server: add the repo's checkout path to `/etc/campanha/repos` on box-one (see `deploy/nightly/README.md`) so the night shift covers it.
