---
description: Bring this repository up to the campanha-dev-standards (templates, gates, docs tree), then migrate existing documentation with doc-keeper.
argument-hint: [--tenant single|multi]
---

# /adopt

1. Ask the user one question if not given: is this project single-tenant or multi-tenant (serves several client organisations)?
2. Run the deterministic part:

    bash "${CLAUDE_PLUGIN_ROOT}/scripts/adopt.sh" "$PWD" --tenant <single|multi>

3. Show the report. For every `needs-review` line, and whenever the repo already had documentation, invoke the `doc-keeper` agent in **mode bootstrap**. It moves existing content into the standard tree and writes `docs/dev/research/<date>-adopt-report.md`. It never deletes sources.
4. Apply the conflict policy to anything in existing instructions that contradicts the standard:
   - Security or gate rule (secrets, --no-verify, db push, tests): standard wins; remove the old rule; list it.
   - Convention (naming, hosting, typography, folder roles): standard wins unless the user confirms an exception → add `key: value — reason` under `## Exceptions` in AGENTS.md.
   - More specific than the standard (domain rules, stack quirks): keep in AGENTS.md or `.claude/rules/`.
   - Sibling projects disagree: draft an ADR in `docs/dev/decisions/` with both options; do not migrate that point; tell the user.
   - Unclassifiable: leave untouched, mark `NEEDS DECISION` in the adopt report.
5. Rewrite `CLAUDE.md` to the short template form (keep it if it is already just `@AGENTS.md` + a few lines). Strip any credentials found in instructions and report where they were (never the value).
6. If there are no tests: add the smallest suite that runs (one smoke test per critical page/action) so pre-push can pass.
7. Run `npx tsc --noEmit`, `npm test -- --run`, and `lefthook run pre-push`. Report failures; do not bypass.
8. Commit on a branch `chore/adopt-standards`. Do not delete any source docs; the user deletes after reviewing the adopt report. End with the `core:handoff` skill.
