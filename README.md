# campanha-dev-standards

One development methodology for every project I work on. Company-agnostic. Claude Code plugin + git hooks + three scanners.

## Install (once per person)

    bash <(curl -fsSL https://raw.githubusercontent.com/stickman874/campanha-dev-standards/main/install.sh)

Then inside Claude Code:

    /plugin marketplace add stickman874/campanha-dev-standards
    /plugin install core@campanha-dev-standards
    /plugin marketplace add openai/codex-plugin-cc
    /plugin install codex@openai-codex

## Bring a project up to standard (once per repo)

    /adopt

## What you get

- Commit: gitleaks + lint + design lint (no hardcoded colours/sizes).
- Push: typecheck + tests + semgrep + trivy. Claude cannot bypass them.
- Claude push: Codex adversarial review + doc-keeper updates docs and CHANGELOG first.
- `docs/dev` (builders) and `docs/product` (users, manuals) kept current by `doc-keeper`.
- `/docs-consolidate` weekly: docs vs code drift → PR.

See `docs/superpowers/specs/` for the design.

## Develop the plugin

    claude --plugin-dir ./plugins/core
    bash tests/run.sh
