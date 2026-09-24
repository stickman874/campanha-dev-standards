# campanha-dev-standards

One development methodology for every project: gates, living docs, cheap workers, cross-vendor review. Company-agnostic. A Claude Code plugin + a copier template.

## Install (once per person)

    curl https://mise.run | sh                           # mise installs the pinned tools per repo
    curl -fsSL https://opencode.ai/install | bash        # opencode; then: opencode auth login → OpenCode Go (one $10 subscription per dev)
    # optional: Codex CLI + the openai/codex-plugin-cc plugin for manual /codex:rescue (review gate off)

Claude-only repos (`backend: claude` at adopt) skip opencode and Codex: workers and docs run on Haiku, review and rescue on Sonnet, as subagents in your session (review and night shift through `claude -p`, since they run outside one), on your Claude Code login.

Codex repos (`backend: codex`): Claude (Opus) orchestrates; worker, rescue and review run on gpt-6-sol with your Codex login (`npm i -g @openai/codex`, `codex login`, plus the openai/codex-plugin-cc plugin). Worker and rescue go through the plugin's `codex:codex-rescue` subagent; review and night shift through `scripts/codex.sh` (`codex exec`). Docs stay on Haiku. Windows: add `[windows] sandbox = "unelevated"` to `~/.codex/config.toml`, or Codex cannot read the repo.

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
    copier copy --trust gh:stickman874/campanha-dev-standards .   # asks project name, tenant, backend (opencode | claude | codex)
    mise install && lefthook install

To pull template updates later: `copier update --trust`. Files you edit by hand — AGENTS.md, docs/, README, CHANGELOG, DESIGN.md, SECURITY.md, .claude/ — are never overwritten.

## What you get

- Commit gates: gitleaks (staged) and eslint, including design lint via `eslint-plugin-better-tailwindcss` (see `docs/dev/how-to/design-lint.md`).
- Push gates (seconds): typecheck, tests, and a read-only DeepSeek review (`scripts/review.sh`, JSON findings, blocks on `high`) only when the diff touches auth, API handlers, db or the gates. Humans can force with `SKIP_REVIEW=1 git push` (commit the log); agents cannot.
- Night shift (`scripts/nightly.sh`, systemd timer on your server, see `deploy/nightly/`): semgrep, trivy, Socket, full review and a docs refresh over everything pushed that day → branch `nightly/<date>` + `docs/dev/reviews/<date>.md`.
- Usage economy: all gruntwork, review and docs run on opencode go (DeepSeek V4.1 Flash), not on the Claude subscription; subagents on Haiku; no Agent Teams; Codex optional. Backend `claude`: same flow on Claude only (Haiku worker/docs, Sonnet reviewer/rescuer, Opus orchestrator). Backend `codex`: Opus orchestrator, gpt-6-sol worker/rescuer/reviewer on the Codex login, Haiku docs.
- Claude hooks: `block-secrets.sh` (secret shapes in command text) and `block-unsafe-bash.sh` (`--no-verify`, `hooksPath`, `prisma db push`/`reset`, `supabase db reset --linked`).
- Secrets: sandbox + `permissions.deny` in the settings template; opencode denies dotenv reads natively.
- `core:worker`, `core:review`, `core:rescue` skills over one runner (`scripts/opencode.sh`, `opencode run --format json`, or `scripts/claude.sh`, `claude -p --agent`, on backend `claude`, or `scripts/codex.sh`, `codex exec`, on backend `codex`); project agents with real permission limits (`worker`, `reviewer`, `docs`).
- `doc-keeper` agent (mode `diff` on request or when a feature ships, `bootstrap` on adopt, `consolidate` weekly) keeps `docs/dev`, `docs/product` and CHANGELOG current.
- `core:handoff` prints a prompt to paste into the next session (any tool).
- Official plugins enabled by the settings template: superpowers, security-guidance, commit-commands, typescript-lsp, playwright, codex, impeccable.
- UI components: shadcn standard (Base UI) first, ReUI (MCP + `reui` skill, installed globally with `REUI_GLOBAL=1 curl -fsSL https://mcp.reui.io/install | node -`) only when shadcn has nothing that fits. Rule in `template/AGENTS.md`, `template/.claude/rules/frontend.md`, how-to in `template/docs/dev/how-to/ui-components.md`.

## Develop the plugin

Needs `jq` and `python` (or `python3`) with PyYAML on `PATH` — `mise use -g jq python` or your OS package manager. Windows: run tests through Git Bash (`bash tests/run.sh`); the hooks and scripts are plain POSIX `sh`/`bash` and run unchanged there, in WSL, in Linux and in macOS.

    claude --plugin-dir ./plugins/core
    bash tests/run.sh

Designs: [2026-09-10](docs/superpowers/specs/2026-09-10-campanha-dev-standards-design.md), [2026-09-15 v2 lean](docs/superpowers/specs/2026-09-15-v2-lean-design.md) and [2026-09-15 v3 opencode go](docs/superpowers/specs/2026-09-15-v3-opencode-go-design.md).
