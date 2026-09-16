# {{ project_name }} — agent instructions

Write all docs, comments and commit messages in English. Product UI language: see docs/product/glossary.md.

## Communication
- Answer in whatever language the user asked in (PT-PT or US-EN).
- Plain language. Technical when it matters, but the devs here are IT people, not programmers — explain a term the first time; don't assume CS fundamentals.
- Be concise: shortest wording that still carries the substance. Cut preamble and recaps. Save tokens.
- Multiple choice: use the Claude Code option selector, and mark one option `(recommended)`.

## Models
- Orchestrator (plans, decides, reviews): the tool's strongest model. Never Kimi.
- Worker (well-scoped edits and code searches): DeepSeek V4.1 Flash via opencode if you have opencode-go; otherwise Sonnet. The orchestrator commits.
- On a quota or rate-limit error, fall back to the next option and say so in one line. Retry the worker once at the next milestone, never in a loop.
- Worker returned partial or failing work: one correction round with the exact failure, then the fallback or the orchestrator. No retry loops.
- Without Claude: `opencode run --agent worker --auto "<task>"` from the repo (agent in `.opencode/agents/`, no shell).

## Code navigation
- Prefer the language server over grep or reading whole files when the tool has one (the LSP tool in Claude Code and opencode): `workspaceSymbol` to find a definition, `findReferences` for usages, `goToDefinition`/`goToImplementation` to jump to source, `hover` for types without reading the file.
- Grep only for plain text (comments, strings, config) or when no language server is available.
- After editing code, check the diagnostics (type errors) and fix them before moving on.

## Commands
- dev: `npm run dev`
- test: `npm test -- --run`
- typecheck: `npx tsc --noEmit`
- lint: `npx eslint .`

## Where things are
- Current-state docs for builders: `docs/dev/` (architecture, how-to, reference, explanation). Read `docs/dev/architecture.md` first.
- Product behaviour and business rules: `docs/product/features/`. Rules live there once; do not restate them in code comments or dev docs.
- Decisions: `docs/dev/decisions/` (MADR). History: `docs/dev/{specs,plans,research,handoffs}/`.
- Handoffs arrive as a pasted prompt; `docs/dev/handoffs/` holds only the ones written on request.

## Conventions
- Files kebab-case, components PascalCase, constants UPPER_SNAKE, database snake_case.
- TypeScript everywhere in `src/`. No state-management library; React hooks only.
- Design: `DESIGN.md` is the source of truth. Use tokens from `globals.css` and canonical components. Never inline colours, sizes or ad-hoc tables; add missing pieces globally. The pre-commit eslint step fails otherwise (docs/dev/how-to/design-lint.md).
- UI components: shadcn standard (Base UI) first; only when no shadcn primitive or block covers the need, ReUI via its MCP + `reui` skill (see docs/dev/how-to/ui-components.md). Never hand-roll what either registry ships (tables → ReUI `data-grid`, boards → `kanban`). Install through `scripts/ui-add.sh`, never by copying source.
- Tests are mandatory; pre-push runs them. New behaviour ships with a test.
- Secrets: never in the repo; only `.env.example`. Never read `.env*` files.
- Database: migrations are never edited once applied. Never `db push`/`reset` against a shared database.
- Tenant model: {{ tenant }}. If `multi`: row-level isolation by tenant is enforced in the database, never only in app code.
- Hosting: Dokploy on Hetzner unless declared under Exceptions.

## Gates (do not bypass)
- commit: gitleaks, eslint (incl. design lint).
- push: typecheck, tests; `scripts/review.sh` (DeepSeek, read-only) when the diff touches auth, API handlers, db or the gates.
- night shift (server): semgrep, trivy, Socket, review of everything pushed, docs refresh → branch `nightly/<date>` and `docs/dev/reviews/<date>.md`. Read the latest report at session start.
- Humans may force a push with `SKIP_REVIEW=1 git push` (logged in `docs/dev/reviews/skipped.log` — commit that file; reviewed at night). Agents may not.

## Exceptions
<!-- Declared divergences from the standard: `key: value — reason`. Undeclared divergence fails the weekly consolidation. -->
