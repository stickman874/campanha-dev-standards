# campanha-dev-standards

One development methodology for every project: gates, living docs, cheap workers, cross-vendor review. Company-agnostic. A Claude Code plugin + a copier template.

## Install (once per person)

    curl https://mise.run | sh   # mise installs the pinned tools per repo
    codex login                  # Codex CLI comes from mise inside an adopted repo; a ChatGPT plan is required for the pre-push review
    # optional: opencode with an opencode-go subscription for the DeepSeek worker (otherwise Sonnet is used)

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

## Adopt a repo (once per repo)

Inside Claude Code run `/adopt`. Or by hand:

    copier copy --trust gh:stickman874/campanha-dev-standards .
    mise install && lefthook install

To pull template updates later: `copier update --trust`. Files you edit by hand — AGENTS.md, docs/, README, CHANGELOG, DESIGN.md, SECURITY.md, .claude/ — are never overwritten.

## What you get

- Commit gates: gitleaks (staged) and eslint, including design lint via `eslint-plugin-better-tailwindcss` (see `docs/dev/how-to/design-lint.md`).
- Push gates run by lefthook for humans and agents alike: typecheck, tests, semgrep, trivy, docs-check and a Codex adversarial review via `scripts/codex-review.sh` — routine diffs on `gpt-5.6-sol`/medium, sensitive diffs on `gpt-6-astra`/medium; blocks on `VERDICT: block`.
- Claude hooks: `block-secrets.sh` (secret shapes in command text) and `block-unsafe-bash.sh` (`--no-verify`, `hooksPath`, `prisma db push`/`reset`, `supabase db reset --linked`).
- Secrets: sandbox + `permissions.deny` in the settings template; opencode denies dotenv reads natively.
- `core:worker` skill: `scripts/worker.sh` runs DeepSeek V4.1 Flash through the project's no-shell opencode agent (`.opencode/agents/deepseek-worker.md`), gives up early on usage limits and falls back to Sonnet.
- `doc-keeper` agent (mode `diff` before push, `bootstrap` on adopt, `consolidate` weekly) keeps `docs/dev`, `docs/product` and CHANGELOG current.
- `core:handoff` skill.
- Official plugins enabled by the settings template: superpowers, security-guidance, commit-commands, typescript-lsp, playwright, codex, impeccable.

## Develop the plugin

    claude --plugin-dir ./plugins/core
    bash tests/run.sh

Designs: [2026-09-10](docs/superpowers/specs/2026-09-10-campanha-dev-standards-design.md) and [2026-09-15 v2 lean](docs/superpowers/specs/2026-09-15-v2-lean-design.md).
