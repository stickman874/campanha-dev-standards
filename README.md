# campanha-dev-standards

One development methodology for every project I work on. Company-agnostic. Claude Code plugin + git hooks + three scanners.

## Install (once per person)

    bash <(curl -fsSL https://raw.githubusercontent.com/stickman874/campanha-dev-standards/main/install.sh)

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

- Commit: gitleaks + lint + design lint (no hardcoded colours/sizes). `scripts/design-lint.sh` is vendored into each project by `/adopt` — no machine-local path in the committed `lefthook.yml`.
- Push: typecheck + tests + semgrep + trivy. Claude is blocked from bypassing them with --no-verify.
- opencode: the same Bash hooks run inside opencode via `plugins/core/opencode/guard.js` (linked by `install.sh`; rerun it after adding the marketplace). For code navigation there too, add `"lsp": true` to `~/.config/opencode/opencode.jsonc` and `export OPENCODE_EXPERIMENTAL_LSP_TOOL=true`.
- `core:deepseek-worker` agent: hand off scoped edits/searches to DeepSeek V4.1 Flash via a no-shell opencode agent (`install.sh` links it to `~/.config/opencode/agents/`); falls back to Sonnet if opencode, the guard or DeepSeek itself is unavailable.
- Code navigation: `/adopt` enables the official LSP plugin for the project's stack (TS, Python, Go, Rust, PHP, C#, Java, Swift, C/C++).
- Claude push: Codex adversarial review + doc-keeper updates docs and CHANGELOG first.
- `security-posture` and `handoff` skills: a judgment checklist for auth/data/API/PII diffs, and end-of-work-block handoff notes in `docs/dev/handoffs/`.
- `/adopt [--tenant single|multi]`: bring a repo up to the standard, idempotently.
- `docs/dev` (builders) and `docs/product` (users, manuals) kept current by `doc-keeper`.
- `/docs-consolidate` weekly: docs vs code drift → PR.

See `docs/superpowers/specs/` for the design.

## Develop the plugin

    claude --plugin-dir ./plugins/core
    bash tests/run.sh
