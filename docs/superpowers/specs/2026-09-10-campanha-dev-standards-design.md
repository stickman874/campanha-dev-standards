# campanha-dev-standards — Design

Date: 2026-09-10 · Status: draft for owner review · Language of all docs: English

## 1. Purpose

One development methodology for every project the owner works on — the owner's companies and personal — that a second developer can adopt in 15 minutes and that does not depend on any single AI vendor.

Problems it must solve, in priority order:

1. **Shared context**: two people and two Claude sessions on the same repo without knowing what the other decided or changed.
2. **Quality gates**: code reaching production without independent review or tests.
3. **Living documentation**: specs and plans pile up; nobody maintains "the current state", and the docs must later feed user manuals.
4. **Security & compliance**: the team has CS training but no professional security practice; scanners and a checklist must run without anyone remembering.

Non-goals: building an orchestrator, dashboards, or company-specific "brains". Herdr is a terminal multiplexer and stays that.

## 2. Principles

- Git is the source of truth. Knowledge lives in the repo, not in a model.
- Deterministic tools where a tool exists (scanners, linters, hooks); AI only where judgment is needed (review, docs, security posture).
- Maximum off-the-shelf: official plugins and stock binaries. Custom code is limited to what nobody sells.
- Company-agnostic: nothing in the standard names the owner's companies or a client. Company infra stays in the user's global `CLAUDE.md`.
- Humans approve merges to production and any doc consolidation PR.

## 3. Architecture

### 3.1 Distribution

- Repo `stickman874/campanha-dev-standards` (public, personal GitHub) is a **Claude Code plugin marketplace** with one plugin, `core`.
- Install once per person: `/plugin marketplace add <owner>/campanha-dev-standards` then `/plugin install core@campanha-dev-standards`. Update with `/plugin update`.
- Each repo carries `.claude/settings.json` with `enabledPlugins: {"core@campanha-dev-standards": true}` so a fresh clone activates the plugin on trust.
- Development of the plugin itself: `claude --plugin-dir ./plugins/core`.

### 3.2 Layers

| Layer | Component | Source |
|---|---|---|
| Official plugins | `superpowers` (method), `codex-plugin-cc` (OpenAI; Codex as reviewer), `claude-security` (deep audit on demand), `impeccable` (design system), `playwright` (browser verification) | marketplaces |
| Binaries | `lefthook`, `gitleaks`, `semgrep`, `trivy`, Playwright CLI + Chrome (`npx playwright install chrome`) | `install.sh` in this repo |
| Plugin `core` (custom) | 2 hooks, 1 agent, 2 skills, 1 command, templates | this repo |

Semgrep Guardian (per-file live scanning) is **deferred**: start with semgrep in pre-push; enable Guardian only if pre-push security failures become frequent.

### 3.3 Plugin `core` contents

```
plugins/core/
  .claude-plugin/plugin.json
  hooks/
    block-unsafe-bash.sh      PreToolUse(Bash): reject --no-verify, --no-gpg-sign, reading .env* (except .env.example), db push/reset against non-local DBs
    pre-push-gate.sh          PreToolUse(Bash) on `git push`: run codex adversarial review + doc-keeper, then lefthook pre-push; block push until clean
  agents/
    doc-keeper.md             maintains docs/ (see §5)
  skills/
    security-posture/         judgment checklist run when the diff touches auth, data, API or PII (OWASP Top 10 + GDPR items)
    handoff/                  writes docs/dev/handoffs/YYYY-MM-DD-<person>.md at end of a work block
  commands/
    adopt.md                  /adopt — bring a repo up to the standard (see §7)
  templates/
    AGENTS.md CLAUDE.md SECURITY.md security.txt README.md CHANGELOG.md
    lefthook.yml  .claude/settings.json  .claude/rules/{database,api,frontend}.md
    docs/ skeleton (dev/, product/)
```

## 4. Gates

| Trigger | Runner | Checks | Budget |
|---|---|---|---|
| `git commit` | lefthook pre-commit | gitleaks on staged; eslint on staged; **design lint**: fail on hardcoded colours/sizes (Tailwind arbitrary values, hex in TSX) | seconds |
| `git push` (any) | lefthook pre-push | typecheck, unit + integration tests, `semgrep --config auto`, `trivy fs` (fail on CRITICAL/HIGH) | ≤ 3 min |
| `git push` from Claude | `pre-push-gate.sh` hook | `codex-review` on the diff (DeepSeek for routine diffs, Codex for sensitive/DeepSeek-written diffs) → fix → `doc-keeper` updates docs + CHANGELOG → then lefthook pre-push | + review time |
| Any Bash from Claude | `block-unsafe-bash.sh` | no `--no-verify`, no `.env` reads, no destructive DB commands | — |
| Weekly (scheduled) | `doc-keeper` consolidation | diff `docs/dev/reference` vs code, orphan/stale docs, opens PR for human approval | — |

Manual pushes outside Claude get only the scanners; the weekly consolidation catches missing docs. Accepted.

Tests are **mandatory** in every project (pre-push fails without a passing suite). A few of the ten existing projects have no tests today and get a minimal suite during adoption.

## 5. Documentation

Two audiences, two trees. All docs in English.

```
README.md          standard-readme: what, install, usage, links
CHANGELOG.md       Keep a Changelog 1.1 + SemVer, [Unreleased] on top
SECURITY.md        supported versions, disclosure contact, incident runbook link
AGENTS.md          ≤ ~180 lines: commands, conventions that differ from defaults, gotchas. Read by Claude and Codex.
CLAUDE.md          `@AGENTS.md` + ≤ 20 Claude-specific lines
.claude/rules/     path-scoped rules, loaded only when touching matching files
  database.md      migrations never edited once applied; multi-tenant rule where applicable
  api.md           session check first, input validation, rate limits
  frontend.md      tokens/components only; no hardcoded colours, sizes or ad-hoc tables
DESIGN.md          impeccable design system (tokens, type scale, canonical components)

docs/dev/                      for builders — current state, edited in place
  architecture.md              one page: context + containers diagram (Mermaid), key flows
  decisions/NNNN-title.md      MADR 4.0, append-only
  how-to/                      runbooks: deploy, rollback, rotate secrets, restore backup, incident
  reference/                   data-model.md, env-vars.md, endpoints.md, integrations.md (generated where possible)
  explanation/                 the "why" that is not a single decision (security model, domain concepts)
  specs/ plans/ research/      dated history, append-only (superpowers writes here)
  handoffs/YYYY-MM-DD-<who>.md 4 lines: was doing / left half-done / do not / next step

docs/product/                  for users and manual writers — user language
  features/<feature>.md        what it does, who can use it, steps, business rules, screenshots
  roles.md                     user profiles and what each sees/can do
  glossary.md                  domain terms in the client's language
  manual/                      compiled per role from features/ (generated, not hand-written)
```

Rules enforced by `doc-keeper`:

- On every Claude push, map the diff to targets: schema/env/endpoints → `reference/`; deploy/infra → `how-to/`; decision with rejected alternatives → `decisions/`; UI or behaviour change → `product/features/` (user language; flag "screenshot stale"); everything → `CHANGELOG [Unreleased]`.
- Business rules are written **once**, in `product/features/`; dev docs link to them.
- Never create new files in the "current state" folders beyond the fixed set; edit existing sections. Files over ~800 lines trigger a warning to split, not an automatic split.
- Screenshots are taken by the Playwright headed flow already in use (viewports 1440×900 and 390×844) and deleted from scratch after being placed.
- `handoffs/` replaces `RESUME.md` and `.planning/STATE.md`.
- Weekly consolidation opens a PR; humans approve.

## 6. Conventions encoded in `AGENTS.md` template (owner's preferences)

- Claude answers in the user's language; **all docs and code comments in English**; product UI in pt-PT unless the project says otherwise.
- Method: superpowers. Brainstorm → plan → **owner approval** → implement with subagents → verify. No GSD.
- Models: planning with the active model; implementation subagents DeepSeek V4.1 Flash via opencode (`core:deepseek-worker`) where the dev has opencode-go, otherwise Sonnet (Haiku where it suffices); on a quota error fall back to Sonnet; never Kimi as orchestrator; visual verification by a Sonnet subagent in headed Chrome using playwright, screenshots deleted afterwards.
- Review before push (`codex-review` skill, enforced by the push gate): DeepSeek reviews routine diffs, Codex as fallback; Codex is required for sensitive diffs (auth, personal data, API handlers, uploads, payments, integrations, secrets, the gates themselves) and for any diff carrying DeepSeek's own `Worker: deepseek` trailer, so DeepSeek never reviews its own work; plans go to Codex with DeepSeek as fallback. Codex (official `codex-plugin-cc`, version pinned) also covers: `/codex:adversarial-review` on the **plan** before implementation starts, and `/codex:rescue` only when Claude is stuck on a task, followed by a manual `git diff` check because Codex can report "done" without changes. Codex never implements by default; alternating Claude/Codex per task is out. Revisit `claudex-loop` after two months.
- Secrets local only; only `.env.example` in the repo.
- Hosting: Dokploy on Hetzner by default; Vercel allowed per project (declared in `AGENTS.md`).
- The four multi-tenant projects: row-level isolation enforced in the database, never only in app code. Single-tenant projects declare `tenant: single` and skip the rule.
- Design: `DESIGN.md` mandatory; every screen uses global tokens and canonical components; anything missing is added globally, never inline. Pre-commit design lint enforces it.
- Naming: kebab-case files, PascalCase components, UPPER_SNAKE constants, snake_case DB.
- Ponytail as philosophy at level **lite**, with the caveat: "smallest change at the right level — colours, components and business rules are fixed at the source, never in the screen".

## 7. `/adopt` — bringing a repo up to standard

Runs once per repo. Idempotent.

1. Install lefthook hooks; copy `lefthook.yml`, `SECURITY.md`, `security.txt`, `.claude/settings.json`, `.claude/rules/*` if missing.
2. Create the `docs/dev` and `docs/product` skeleton (only the fixed files; no empty Diátaxis folders beyond the set).
3. **Migration mode** (all 10 current projects): run `doc-keeper` in bootstrap over the existing repo — existing `docs/*`, root `PRD.md`/`PRODUCT.md`/`RESUMO_PROJETO.md`, `.planning/`, oversized `CLAUDE.md` — and distribute content into the new tree. Produces a PR for human review; nothing deleted until approved.
4. Rewrite `CLAUDE.md` to the short template; move project specifics into `AGENTS.md` (≤ 180 lines) and `.claude/rules/`. Strip credentials found in instructions (e.g. seed passwords).
5. Add a minimal test suite if none exists so pre-push can run.
6. Report: what was created, what was moved, what needs a human decision (e.g. contradictions between two projects sharing a codebase).

### 7.1 Conflict resolution during `/adopt`

Existing instructions will contradict the standard. Fixed policy, applied by the migration and recorded in the adopt report:

| Situation | Rule |
|---|---|
| Project rule contradicts a **security or gate** rule (secrets, `--no-verify`, `db push`, tests) | Standard wins. Old rule removed. Listed in the report. |
| Project rule contradicts a **convention** (naming, hosting, typography, folder roles) | Standard wins **unless** the project keeps it as a declared exception: an `## Exceptions` section in `AGENTS.md` with the rule and a one-line reason (e.g. `hosting: vercel — client contract`). `/adopt` proposes the exception, the human confirms. |
| Project rule is **more specific** than the standard (domain rules, stack quirks) | Not a conflict. Kept in `AGENTS.md` or `.claude/rules/`. |
| Two projects sharing a codebase disagree with each other | Neither is migrated on that point; the item goes to a `docs/dev/decisions/` draft ADR with both options, resolved once by the human, then applied to both. |
| Rule cannot be classified | Left untouched, flagged `NEEDS DECISION` in the report. |

Nothing is deleted before the human reviews the adopt PR. Exceptions are the only mechanism for divergence; undeclared divergence is a lint failure in the weekly consolidation.

## 8. Security & compliance checklist (enforced or reviewed)

Enforced by tools: no secrets in repo; no CRITICAL/HIGH CVEs; SAST clean; SBOM generated per release (`trivy sbom`); `.env` unreadable by agents.

Reviewed by `security-posture` skill when the diff touches auth/data/API: session and permission checks first; input validation; rate limiting; PII inventory updated in `docs/dev/explanation/security.md`; no PII or secrets in logs; secure headers/cookies.

Documents: `SECURITY.md` + `public/.well-known/security.txt`; `docs/dev/how-to/incident.md` with the three clocks (GDPR 72h to CNPD; CRA 24h/72h/14d if ever in scope; NIS2 24h/72h if a client demands it).

## 9. Rollout

1. Done today: unified git identity (one name/email across the owner's companies; a separate noreply identity for personal repos).
2. Build `core` plugin + `install.sh` (one session). Test with `--plugin-dir` on the pilot project.
3. Pilot: `/adopt` on the pilot project for two weeks with both developers.
4. Adopt the remaining 9 projects. Resolve the recorded contradictions (typography for numbers, `components/ui` role, RLS function) once, for the two projects sharing a codebase together.
5. Revisit after two months: Semgrep Guardian, `claude-security` scheduling, anything from the partner's "phase 3" that is still missing.

## 10. Open items

- GitHub home for the marketplace repo (org vs personal).
- Contradictions between the two projects sharing a codebase (owner declined to decide now; recorded for the pilot).
- Whether the weekly consolidation runs as a Claude `/schedule` routine or via the existing cron-based agent pattern from the vault.
- Codebase map tooling (graphify/Serena/claude-mem): none adopted; revisit Serena on the largest repo if navigation pain persists after two weeks of docs-in-repo. Graphify star count looks inflated (2026-09-10 research).
