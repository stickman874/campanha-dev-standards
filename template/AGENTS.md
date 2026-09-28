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
- Execute a plan in batches: tasks that touch the same files go in one batch, in order. Batches are independent when they change no file in common and neither needs the other's output; independent batches run in parallel, one worker each in its own worktree. A dependent batch starts from the commit that already contains its prerequisites. Never queue several batches on one worker.
- The orchestrator merges: one batch at a time, in dependency order; it reads the diff, resolves conflicts itself, and reruns the affected tests on the merged result.
- No review per task. After merging a batch that touches sensitive paths, start the background `scripts/review.sh` (see Gates); routine batches get the orchestrator's reading now and the night shift's review later. Measured: per-task review loops took most of each task's 13-42 min and still missed a defect the push review found; background reviews took 5-6 min per batch and caught 1 high and 2 medium before the push.
- Don't wait idle: while a worker, a review or a push runs, start the next independent batch if there is one. Before calling the plan done, collect every worker and review result.
- Separate plans run in separate sessions and worktrees; independent problems (bugs, investigations) are dispatched together.
- Commit before dispatching: parallel workers start from the last commit in their own worktree and never see uncommitted changes.
- Worktrees: whoever starts a dev server or other background process in a worktree stops it when its batch is merged (never `disown`); use a free port; the orchestrator removes the worktree after merging the batch.

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
- push: typecheck, tests related to the changed files (`vitest related`); `scripts/review.sh` (DeepSeek on opencode go, read-only) when the diff touches auth, API handlers, db or the gates — extra sensitive paths per repo: `.review-paths`, one regex per line. Blocked: read the `[high]` lines, fix, commit, push again; max 3 rounds, then show the findings to the user. Approved commits are remembered (`.git/review-approved`), so the push reviews only what came after; run `bash scripts/review.sh <base>` in the background after each batch of commits that touches sensitive paths and keep working while it runs.
- night shift (server): full test suite, semgrep, trivy, Socket, review of everything pushed, docs refresh → branch `nightly/<date>` and `docs/dev/reviews/<date>.md`. Read the latest report at session start.
- Humans may force a push with `SKIP_REVIEW=1 git push` (logged in `docs/dev/reviews/skipped.log` — commit that file; reviewed at night). Agents never do it.

## Exceptions
<!-- Declared divergences from the standard: `key: value — reason`. Undeclared divergence fails the weekly consolidation. -->
