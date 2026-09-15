# campanha-dev-standards v3 — opencode go as worker, reviewer and night shift

Date: 2026-09-15 · Status: draft for owner review · Supersedes the review, worker, handoff and push-gate sections of `2026-09-15-v2-lean-design.md` (D1, D2, D4, D7 partly, D14). Docs tree, conventions, copier, mise, hooks and secrets rules stay.

## Why

v2 made the gates lean but kept Codex as the judge on every sensitive push. Two facts changed the picture (research: `docs/superpowers/research/2026-09-15-agentic-workflow-tooling.md` plus the 2026-09-15 follow-up on opencode go and community plugins):

- Codex on a ChatGPT Plus plan gives 3–30 messages per 5 h on the heavy model. It cannot be the reviewer of record; the team already feels it as "underwhelming".
- opencode go ($10/dev/month, dollar-capped per model, zero-data-retention on `deepseek-v4.1-flash` confirmed on the official page, to be re-checked monthly) gives a separate quota that is not the Claude subscription and not the Codex plan.

Team constraints unchanged: 3 vibecoders, client-code privacy, no CI service, pushes must take seconds, zero ritual on small tasks.

## Decisions

| # | Decision | Replaces |
|---|---|---|
| E1 | **One engine for everything that is not a decision:** `opencode run --format json --agent <agent>` on `opencode-go/deepseek-v4.1-flash`. Claude Code stays the orchestrator; Codex becomes optional (`/codex:rescue` by hand, review gate off). Model id in one place (`OPENCODE_MODEL` env, default in the agent frontmatter). | Codex in `codex-review.sh`; DeepSeek only as worker |
| E2 | **Three project-level opencode agents** in `template/.opencode/agents/`: `worker` (edit/write allowed; bash/task denied, as today), `reviewer` (read/grep/glob only; edit/write/bash/task denied), `docs` (write only under `docs/` and `CHANGELOG.md`; bash denied). Capability restriction by agent permission config, never by prompt wording. Agents run in the repo checkout, never in a worktree, and have no shell, so they never need `.env`; the agent prompt says so explicitly ("you cannot run the app or the tests; do not ask for env files; the caller runs them"). Non-secret config a task needs goes in the brief. | `deepseek-worker.md` alone; workers asking for `.env` copies into worktrees |
| E3 | **Push blocks on three things only:** gitleaks (commit), typecheck + tests, and `review.sh` on sensitive paths (auth, session, payments, API handlers, migrations, `.claude/`, `.opencode/`, `lefthook.yml`, `scripts/`). semgrep, trivy, docs-check leave the push. Push time target: seconds, plus one DeepSeek review when sensitive. | v2 D14 gate list |
| E4 | **Night shift on box-one (Hetzner).** A systemd timer runs `scripts/nightly.sh` per adopted repo: fetch, diff since last run, semgrep, trivy, Socket (`npx socket`), `review.sh` over the whole day's range (routine paths included), `docs` agent to refresh `docs/` and `CHANGELOG.md`. Output: branch `nightly/YYYY-MM-DD` with the docs commit and `docs/dev/reviews/YYYY-MM-DD.md` (findings, severities, `file:line`). Nothing pushed to `main`. Server holds one opencode login (a dedicated go subscription, not a dev's) and one read/write deploy key per repo. | docs-check blocking; doc-keeper before every push; semgrep/trivy in pre-push |
| E5 | **Review output is structured, not a sentence.** `reviewer` returns JSON `{verdict: approve\|block, findings:[{severity, file, line, what, fix}]}`; `review.sh` validates with `jq`: missing/invalid JSON = block; `approve` with any `high` finding = block. | `VERDICT:` last-line grep |
| E6 | **Worker output is verified, not trusted.** `worker.sh` parses the JSON event stream: usage-limit/auth/error events → exit 3 (`DEEPSEEK_UNAVAILABLE`, Claude falls back to a Sonnet subagent); ≥3 tool calls and no file changed → exit 4 ("wrote nothing", reported as failure); files the worker claims vs `git status --porcelain` are cross-checked and mismatches listed. | stdout grep for rate-limit strings |
| E7 | **`core:rescue` skill:** when Claude is stuck, a fresh DeepSeek session (`worker` agent) gets the problem statement, the failing command and its output; Claude verifies with `git diff` and the test before trusting "done". Rule: whoever wrote the code never grades it; rescue output goes through `review.sh` when it touches sensitive paths. `/codex:rescue` stays as the manual escalation when DeepSeek fails twice. | nothing (new) |
| E8 | **`core:handoff` outputs a prompt.** A paste-ready block in the second person (repo, branch, what was being done, what is half-done with failing test and path, what not to do, next step; plus `git status --short` and `diff --stat`). No file, no question. A `.md` in `docs/dev/handoffs/` only when the user asks for one explicitly. Session-start "read newest handoff" rule dropped. | 4-heading `.md` handoff |
| E9 | **Claude usage rules in the template** stay: Haiku subagents (`CLAUDE_CODE_SUBAGENT_MODEL`), no Agent Teams, heavy work off-peak, handoff prompt to jump tools when the quota ends. | — |
| E10 | **Dependencies:** `mise.toml` drops `npm:@openai/codex`; opencode is required (`mise` cannot install it: documented one-liner). Socket runs via `npx`, no install. Codex plugin stays in `enabledPlugins` as optional; `codex login` leaves the README install list. | v2 D9 tool list |
| E11 | **Not copied from community plugins:** `--dangerously-skip-permissions` posture, worktree-per-worker, cost ledgers, dashboards, free-tier models with data retention, claudex-loop (spends more tokens by design). | — |
| E12 | **The human can always push; the agent never bypasses.** `git push --no-verify` typed by a person (terminal, or `!` prefix in Claude Code) is never blocked. Finer, auditable option: `SKIP_REVIEW=1 git push` skips only `review.sh` (typecheck and tests still run); `review.sh` appends the range to `docs/dev/reviews/skipped.log` and the night shift reviews it anyway, marking the report "pushed without review". `block-unsafe-bash.sh` (Claude) and the opencode agents' bash permission deny `--no-verify`, `LEFTHOOK=0`, `core.hooksPath` and `SKIP_REVIEW=1` when the agent writes the command; the agent reports why the review blocked and tells the user the exact command to force it themselves. | opencode sessions blocked on a Codex review with no human override |

## Layout after v3

```
plugins/core/
  scripts/opencode.sh          # shared: run one agent, parse JSON events, classify exit (ok/limit/hang/fail/nothing)
  scripts/worker.sh            # E6, thin over opencode.sh
  scripts/review.sh            # E5; args: <from> <to> | pre-push stdin; sensitive-path filter unless --all
  scripts/nightly.sh           # E4; runs on the server; uses review.sh --all and the docs agent
  skills/{worker,review,rescue,handoff}/SKILL.md
  agents/doc-keeper.md         # kept for manual mode diff / bootstrap
  commands/{adopt,docs-consolidate}.md
  hooks/                       # unchanged
template/
  .opencode/agents/{worker,reviewer,docs}.md
  lefthook.yml                 # pre-commit: gitleaks, eslint; pre-push: typecheck, test, review (use_stdin)
  scripts/review.sh            # copied so lefthook needs no plugin path (same file as plugins/core/scripts)
  mise.toml                    # minus codex
  docs/dev/reviews/.gitkeep
deploy/nightly/                # this repo: systemd unit + timer + install notes for box-one; repo list in a server-local file, never committed
```

## Flows

**Worker (Claude → DeepSeek):** Claude writes a self-contained task (files, done-condition) → `worker.sh` refuses on a dirty tree → `opencode run --agent worker --format json` → events parsed → exit code + `git status` summary + claimed-vs-real file list → Claude runs the relevant test, one correction round, commits.

**Pre-push review:** lefthook pipes the push ranges → `review.sh` diffs each range → no sensitive path → "skipped (routine; nightly will review)" → else `opencode run --agent reviewer` with the range and the section-structured prompt (role, attack surface, finding bar, grounding rules, output schema) → JSON validated → block prints findings as `[high] file:line - what - fix`.

**Nightly (server):** timer → for each repo in the server-local list: `git fetch`, range = last reviewed sha..origin/main → semgrep/trivy/Socket to the report → `review.sh --all` → `docs` agent on branch `nightly/<date>` → commit "docs: nightly refresh <date>" + report → push the branch only. Last reviewed sha stored in the report. Any tool missing or quota exhausted → report says so, exit non-zero, timer retries next night; never silent.

**Rescue:** `core:rescue` skill → `worker.sh` with a rescue brief (problem, command, output, constraints) → Claude verifies → if it touched sensitive paths, `review.sh` before commit.

## Error handling

- opencode missing, not logged in, `FreeUsageLimitError`/usage-limit event, timeout (default 600 s worker, 300 s review): worker → exit 3 and Claude falls back to Sonnet; review in pre-push → **block with the reason** (never approve on failure); nightly → recorded in the report.
- Reviewer JSON invalid → block. Reviewer tries to edit (should be impossible by permissions) → block and log.
- Nightly on a repo with no new commits → skip, report one line.
- ZDR check: `nightly.sh` prints the date of the last manual confirmation of the opencode go privacy table; older than 35 days → warning at the top of the report.

## Testing

Behaviour tests only, fake `opencode` binary emitting JSON events (modes `ok`, `limit`, `hang`, `fail`, `nothing`, `edit-outside`, `bad-json`, `approve-with-high`): `worker.test.sh` (updated), `review.test.sh` (replaces `codex-review.test.sh`), `nightly.test.sh` (fake repo, fake semgrep/trivy/socket that print fixed findings, asserts branch, report file and exit code), `handoff` covered by a skill frontmatter parse only (prompt content is not asserted). `e2e.test.sh` keeps the copier render and the lefthook config load.

## Open items (owner)

- Dedicated opencode go subscription for the server (E4) vs reusing one dev's login.
- Which repos the night shift covers first (server-local list).

## Out of scope

Starter Next/Prisma skeleton (pain 3 "control the input"): separate spec. Socket paid features. Any GitHub Actions.
