# {{ project_name }} — agent instructions

Write all docs, comments and commit messages in English. Product UI language: see docs/product/glossary.md.

## Communication
- Answer in whatever language the user asked in (PT-PT or US-EN).
- Plain language. Technical when it matters, but the devs here are IT people, not programmers — explain a term the first time; don't assume CS fundamentals.
- Be concise: shortest wording that still carries the substance. Cut preamble and recaps. Save tokens.
- Multiple choice: use the tool's option selector, and mark one option `(recommended)`.

## Models
- Orchestrator (plans, decides, reviews, commits): Claude Code → Opus; opencode → the `orchestrator` agent (gpt-6-sol). Never Kimi.
- Claude Code: the superpowers skills own the process; see `CLAUDE.md`.
- opencode: subagents in `.opencode/agents/`; how to brief and verify them is in `.opencode/agents/orchestrator.md`.
- On a quota or rate-limit error, fall back to the next option and say so in one line. No retry loops.

## Parallel work
- Parallelise as much as possible: split work into independent, non-overlapping tasks (different files or modules) and dispatch them all at once.
- Serialise only when one task consumes another's output or two tasks touch the same file. Sequential dispatch is the exception, not the default.
- Commit before dispatching: parallel workers start from the last commit in their own worktree and never see uncommitted changes.

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
- push: typecheck, tests related to the changed files (`vitest related`); `scripts/review.sh` (DeepSeek on opencode go, read-only) when the diff touches auth, API handlers, db or the gates — extra sensitive paths per repo: `.review-paths`, one regex per line. Blocked: read the `[high]` lines, fix, commit, push again; max 3 rounds, then show the findings to the user. On demand: `bash scripts/review.sh <base>`.
- night shift (server): full test suite, semgrep, trivy, Socket, review of everything pushed, docs refresh → branch `nightly/<date>` and `docs/dev/reviews/<date>.md`. Read the latest report at session start.
- Humans may force a push with `SKIP_REVIEW=1 git push` (logged in `docs/dev/reviews/skipped.log` — commit that file; reviewed at night). Agents never do it.

## Exceptions
<!-- Declared divergences from the standard: `key: value — reason`. Undeclared divergence fails the weekly consolidation. -->
