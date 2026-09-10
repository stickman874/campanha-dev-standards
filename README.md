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

## Bring a project up to standard (once per repo)

    /adopt

## What you get

- Commit: gitleaks + lint + design lint (no hardcoded colours/sizes). `scripts/design-lint.sh` is vendored into each project by `/adopt` — no machine-local path in the committed `lefthook.yml`.
- Push: typecheck + tests + semgrep + trivy. Claude is blocked from bypassing them with --no-verify.
- Claude push: Codex adversarial review + doc-keeper updates docs and CHANGELOG first.
- `security-posture` and `handoff` skills: a judgment checklist for auth/data/API/PII diffs, and end-of-work-block handoff notes in `docs/dev/handoffs/`.
- `/adopt [--tenant single|multi]`: bring a repo up to the standard, idempotently.
- `docs/dev` (builders) and `docs/product` (users, manuals) kept current by `doc-keeper`.
- `/docs-consolidate` weekly: docs vs code drift → PR.

See `docs/superpowers/specs/` for the design.

## Develop the plugin

    claude --plugin-dir ./plugins/core
    bash tests/run.sh
