# {{PROJECT}} — agent instructions

Write all docs, comments and commit messages in English. Product UI language: see docs/product/glossary.md.

## Communication
- Answer in whatever language the user asked in (PT-PT or US-EN).
- Plain language. Technical when it matters, but the devs here are IT people, not programmers — explain a term the first time; don't assume CS fundamentals.
- Be concise: shortest wording that still carries the substance. Cut preamble and recaps. Save tokens.
- Multiple choice: use the Claude Code option selector, and mark one option `(recommended)`.

## Commands
- dev: `npm run dev`
- test: `npm test -- --run`
- typecheck: `npx tsc --noEmit`
- lint: `npx eslint .`

## Where things are
- Current-state docs for builders: `docs/dev/` (architecture, how-to, reference, explanation). Read `docs/dev/architecture.md` first.
- Product behaviour and business rules: `docs/product/features/`. Rules live there once; do not restate them in code comments or dev docs.
- Decisions: `docs/dev/decisions/` (MADR). History: `docs/dev/{specs,plans,research,handoffs}/`.
- Latest handoff: newest file in `docs/dev/handoffs/`. Read it at session start.

## Conventions
- Files kebab-case, components PascalCase, constants UPPER_SNAKE, database snake_case.
- TypeScript everywhere in `src/`. No state-management library; React hooks only.
- Design: `DESIGN.md` is the source of truth. Use tokens from `globals.css` and canonical components. Never inline colours, sizes or ad-hoc tables; add missing pieces globally. The pre-commit design lint fails otherwise.
- Tests are mandatory; pre-push runs them. New behaviour ships with a test.
- Secrets: never in the repo; only `.env.example`. Never read `.env*` files.
- Database: migrations are never edited once applied. Never `db push`/`reset` against a shared database.
- Tenant model: {{TENANT}}. If `multi`: row-level isolation by tenant is enforced in the database, never only in app code.
- Hosting: Dokploy on Hetzner unless declared under Exceptions.

## Gates (do not bypass)
- commit: gitleaks, eslint, design-lint.
- push: typecheck, tests, semgrep, trivy. Then Codex adversarial review and doc-keeper when pushing from an agent.

## Exceptions
<!-- Declared divergences from the standard: `key: value — reason`. Undeclared divergence fails the weekly consolidation. -->
