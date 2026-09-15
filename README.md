# campanha-dev-standards

One development methodology for every project I work on. Company-agnostic. Claude Code plugin + git hooks + three scanners.

## Install (once per person)

    curl https://mise.run | sh   # (once per machine; then `mise install` inside any adopted repo installs lefthook, gitleaks, semgrep, trivy, codex, copier)

Then inside Claude Code:

    /plugin marketplace add stickman874/campanha-dev-standards
    /plugin install core@campanha-dev-standards
    /plugin marketplace add openai/codex-plugin-cc
    /plugin install codex@openai-codex

Pin the Codex plugin version after installing: `/plugin install codex@openai-codex@<version>` (check `/plugin list`).

## Personal preferences (optional, once per person)

Team communication defaults ship in each repo's `AGENTS.md` (read by Claude and Codex). To also apply them globally across all your projects, paste this into your `~/.claude/CLAUDE.md`:

    ## Personal preferences
    - Language: answer in whatever language I asked in — PT-PT or US-EN.
    - Register: plain language; the devs here are IT people, not programmers — explain a term the first time, don't assume CS fundamentals.
    - Concise, always: shortest wording that carries the substance. Cut preamble and recaps. Save tokens.
    - Multiple choice: use the Claude Code option selector, and mark one option (recommended).

## Bring a project up to standard (once per repo)

    /adopt

## What you get

- Commit: gitleaks + eslint (design lint via eslint-plugin-better-tailwindcss, see the how-to in each project).
- Push: typecheck + tests + semgrep + trivy. Claude is blocked from bypassing them with --no-verify.
- `core:deepseek-worker` skill: `scripts/deepseek.sh` hands scoped edits/searches to DeepSeek V4.1 Flash through a no-shell opencode agent (no model relays the task), runs the task's `Test:` command for it with one correction round and gives up at the first usage-limit error; falls back to Sonnet if opencode or DeepSeek is unavailable.
- Code navigation: `/adopt` enables the official LSP plugin for the project's stack (TS, Python, Go, Rust, PHP, C#, Java, Swift, C/C++).
- Claude push: independent review (DeepSeek for routine diffs, Codex required for sensitive ones and plans) + doc-keeper updates docs and CHANGELOG first.
- `handoff` skill: end-of-work-block handoff notes in `docs/dev/handoffs/`.
- Secrets: Claude Code sandbox + `permissions.deny` for dotenv files (settings template); opencode denies dotenv reads natively.
- `/adopt [--tenant single|multi]`: bring a repo up to the standard, idempotently.
- `docs/dev` (builders) and `docs/product` (users, manuals) kept current by `doc-keeper`.
- `/docs-consolidate` weekly: docs vs code drift → PR.

See `docs/superpowers/specs/` for the design.

## Develop the plugin

    claude --plugin-dir ./plugins/core
    bash tests/run.sh
