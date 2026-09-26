# campanha-dev-standards

One development methodology for every project: gates, living docs, cross-vendor review, a night shift. Company-agnostic. A Claude Code plugin + a copier template.

## Install (once per person)

    curl https://mise.run | sh                           # mise installs the pinned tools per repo
    # then activate it in your shell (once): bash `echo 'eval "$(mise activate bash)"' >> ~/.bashrc`,
    # zsh `echo 'eval "$(mise activate zsh)"' >> ~/.zshrc`, PowerShell `mise activate pwsh | Out-String | Invoke-Expression` in $PROFILE
    curl -fsSL https://opencode.ai/install | bash        # opencode; then opencode auth login twice: OpenCode Go ($10/dev, push review) and OpenAI (orchestrator)
    npm i -g @openai/codex && codex login                # Codex CLI: reviews specs and plans from Claude Code (plugin openai/codex-plugin-cc, enabled by the template)

Use Claude Code, opencode or both; each runs on its own subagents. Claude Code: Opus orchestrates, the superpowers skills run the process, specs and plans are reviewed by Codex. opencode: the `orchestrator` agent (gpt-6-sol) delegates to `worker`/`reviewer`/`docs` (DeepSeek) and `rescuer` (gpt-6-sol). Push review and night shift run on opencode go.

Then inside Claude Code:

    /plugin marketplace add stickman874/campanha-dev-standards
    /plugin install core@campanha-dev-standards

## Personal preferences (optional, once per person)

Team communication defaults ship in each repo's `AGENTS.md` (read by Claude and Codex). To also apply them globally across all your projects, paste this into your `~/.claude/CLAUDE.md`:

    ## Personal preferences
    - Language: answer in whatever language I asked in — PT-PT or US-EN.
    - Register: plain language; the devs here are IT people, not programmers — explain a term the first time, don't assume CS fundamentals.
    - Concise, always: shortest wording that carries the substance. Cut preamble and recaps. Save tokens.
    - Multiple choice: use the Claude Code option selector, and mark one option (recommended).

## Adopt a repo (once per repo)

Inside Claude Code run `/adopt`. Or by hand:

    mise use -g pipx:copier          # once per machine (or prefix the next line with `uvx`)
    copier copy --trust gh:stickman874/campanha-dev-standards .   # asks project name and tenant
    mise install && lefthook install

To pull template updates later: `copier update --trust`. Files you edit by hand — AGENTS.md, docs/, README, CHANGELOG, DESIGN.md, SECURITY.md, .claude/ — are never overwritten.

## What you get

- Commit gates: gitleaks (staged) and eslint, including design lint via `eslint-plugin-better-tailwindcss` (see `docs/dev/how-to/design-lint.md`).
- Push gates (seconds): typecheck, tests, and a read-only DeepSeek review (`scripts/review.sh`, JSON findings, blocks on `high`) only when the diff touches auth, API handlers, db or the gates. Repos add their own extra sensitive paths in `.review-paths` (one regex per line, not shipped by the template). Humans can force with `SKIP_REVIEW=1 git push` (commit the log); agents are blocked from it (opencode: see the known gap in the v4 spec).
- Night shift (`scripts/nightly.sh`, systemd timer on your server, see `deploy/nightly/`): semgrep, trivy, Socket, full review and a docs refresh over everything pushed that day → branch `nightly/<date>` + `docs/dev/reviews/<date>.md`.
- Process: Claude Code follows superpowers (brainstorm → spec → plan → execution), with Codex reviewing specs and plans (`codex:codex-rescue`, read-only); opencode follows the `## Subagents` contract in `.opencode/agents/orchestrator.md`. Both orchestrators parallelise as much as possible.
- Claude hooks: `block-secrets.sh` (secret shapes in command text) and `block-unsafe-bash.sh` (`--no-verify`, `hooksPath`, `prisma db push`/`reset`, `supabase db reset --linked`).
- Secrets: sandbox + `permissions.deny` in the Claude settings template; opencode denies dotenv reads natively and the `orchestrator` agent's bash permission mirrors the Claude hooks.
- One unattended runner, `scripts/opencode.sh` (`opencode run --format json`), shipped next to `scripts/review.sh` and used by the night shift.
- `doc-keeper` agent (mode `diff` on request or when a feature ships, `bootstrap` on adopt, `consolidate` weekly) keeps `docs/dev`, `docs/product` and CHANGELOG current.
- Plugins enabled by the settings template: core, superpowers, typescript-lsp, codex. Kept lean on purpose (see `docs/superpowers/research/2026-09-26-slowness-and-slim-down.md`). impeccable is known but off: turn it on in a project for UI work. Browser checks use the Playwright CLI, not the plugin.
- UI components: shadcn standard (Base UI) first, ReUI (MCP + `reui` skill, installed globally with `REUI_GLOBAL=1 curl -fsSL https://mcp.reui.io/install | node -`) only when shadcn has nothing that fits. Rule in `template/AGENTS.md`, `template/.claude/rules/frontend.md`, how-to in `template/docs/dev/how-to/ui-components.md`.

## Upgrading to 0.5.0 (any tool)

Tell your agent "apply the 0.5.0 upgrade from the campanha-dev-standards README", or do it by hand:

1. Update the plugin, then in each repo right away: `copier update --trust` (the stale `backend:` answer is ignored; `.opencode/agents/`, `opencode.json` and `scripts/opencode.sh` arrive; unedited `.claude/agents/*` are removed — delete edited ones by hand).
2. `AGENTS.md` and `CLAUDE.md` are never rewritten by copier. In `AGENTS.md`, take from the template's `AGENTS.md`: the last bullet of `## Communication`, the whole `## Models`, `## Where things are` and `## Gates (do not bypass)` sections, and the new `## Parallel work` and `## opencode` sections; keep your own `## Commands`, `## Conventions` and `## Exceptions`. Replace `CLAUDE.md` with the template's, then re-add any project-specific lines you had. An existing `opencode.json`: add `"default_agent": "orchestrator"`. `.claude/settings.json`: set `"model": "opus"`, add the `codex@openai-codex` plugin and the `openai-codex` marketplace.
3. Every dev: opencode go login (the push review needs it), OpenAI login in opencode, and `codex login`.
4. Check — this must print nothing: `grep -rn 'core:worker\|core:rescue\|core:review\|core:handoff\|worker.sh\|backend\|Handoffs arrive\|Sonnet, read-only\|gpt-6-sol, read-only' AGENTS.md CLAUDE.md`
5. Your own files outside the repo, if they mention the old skills: `~/.agents/AGENTS.md` (model routing table), `~/.claude/CLAUDE.md` (worker dispatch line).

## Develop the plugin

Needs `jq` and `python` (or `python3`) with PyYAML on `PATH` — `mise use -g jq python` or your OS package manager. Windows: run tests through Git Bash (`bash tests/run.sh`); the hooks and scripts are plain POSIX `sh`/`bash` and run unchanged there, in WSL, in Linux and in macOS.

    claude --plugin-dir ./plugins/core
    bash tests/run.sh

Designs: [2026-09-10](docs/superpowers/specs/2026-09-10-campanha-dev-standards-design.md), [2026-09-15 v2 lean](docs/superpowers/specs/2026-09-15-v2-lean-design.md) and [2026-09-15 v3 opencode go](docs/superpowers/specs/2026-09-15-v3-opencode-go-design.md), [2026-09-24 v4 native subagents](docs/superpowers/specs/2026-09-24-v4-native-subagents-design.md).
