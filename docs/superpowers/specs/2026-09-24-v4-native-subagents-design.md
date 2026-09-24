# campanha-dev-standards v4 — each tool on its own native subagents

Date: 2026-09-24 · Status: draft for owner review · Target release: 0.5.0 · Supersedes the backend sections of `2026-09-15-v3-opencode-go-design.md` (E1, E6, E7) and the `backend` copier question added in 0.3.0/0.4.0. Gates, hooks, secrets rules, docs tree and night shift stay. Also supersedes v3 E8 (handoff).

## Why

v3 made Claude call opencode (DeepSeek) for every worker task to save Claude quota; 0.3.0 and 0.4.0 added `claude` and `codex` backends behind a copier question. Two facts changed:

- Opus 5.5 is much cheaper than the Fable orchestrator the savings were built for. Handing a task to another CLI still costs the orchestrator the brief, the result, the verification and often a correction round; on small tasks the saving is near zero, and the dev pays for a second tool, a second login and a no-shell worker.
- Three backends mean three runners, three agent sets, three test suites and three install paths for 3 people who are not programmers. Nobody exercises all three day to day.

What keeps real value: a review by a **different vendor** than the one that wrote the work, and the gates, hooks, docs and night shift, which never depended on the backend.

## Decisions

| # | Decision | Replaces |
|---|---|---|
| F1 | **No backends. Each tool runs on its own native process.** Claude Code: superpowers skills plus the built-in `Agent` tool, no project agents. opencode: `.opencode/agents/` through its task tool. Neither calls the other inside a session. Our plugin is the enforcement and infra layer (gates, hooks, settings, night shift, docs, cross-vendor spec review), not a process layer. | copier `backend` question, `_exclude` rules, every `{% if backend %}` |
| F2 | **Claude Code roles: superpowers owns the process.** Orchestrator Opus (`"model": "opus"` in the settings template). Specs, plans and execution follow superpowers (brainstorming, writing-plans, subagent-driven-development with its own implementers and reviewers, systematic-debugging, TDD, finishing). Ad-hoc delegation uses built-in `general-purpose` subagents with an explicit `model` (Haiku for scoped edits, Sonnet when stuck). No `.claude/agents/`: our worker/rescuer/reviewer only duplicated superpowers plus the built-in agent; their one extra, a hard no-shell limit, is not worth three files and a second contract. In-session docs stay with the plugin's `doc-keeper` agent. | `core:worker` / `core:rescue` over `worker.sh`; `template/.claude/agents/` |
| F2b | **opencode worker contract lives in `AGENTS.md`** (under an opencode heading; on Claude, superpowers' execution skills carry the equivalent rules), taken from today's `core:worker` Claude-only section, which is then deleted: brief = `Outcome / Files / Keep / Config`; commit or stash first so every change in `git status` is the worker's; one outcome per call; parallel = one worktree per task (Claude `isolation: "worktree"`; opencode's task tool has no directory parameter, so the opencode orchestrator runs `git worktree add` then one `opencode run --agent worker --dir <worktree>` process per task from its shell; one task at a time can use the native task tool in the main checkout), workers never commit, the orchestrator commits in the worktree and cherry-picks; after return: claimed files vs `git status --short` (claimed but unchanged = false claim), read `git diff`, run the test yourself trimmed, one correction round with the error pasted, then fallback or orchestrator; on error or limit keep or revert the partial changes before handing over; `SensitiveSeen` checked. The orchestrator reading the worker's diff is the other-model check on worker code before it is committed. | worker contract spread over `worker.sh` exit codes and three skill sections |
| F2c | **Both orchestrators parallelise as much as possible** (`AGENTS.md`, shared): split work into independent, non-overlapping tasks (different files or modules) and dispatch them all at once; serialise only when one task consumes another's output or two tasks touch the same file. Sequential dispatch is the exception. | nothing (implicit before) |
| F3 | **opencode roles:** new `orchestrator` agent, `mode: primary`, `model: openai/gpt-6-sol`, `reasoningEffort: medium`, on the dev's OpenAI OAuth login in opencode. `worker`, `reviewer`, `docs` stay on `opencode-go/deepseek-v4.1-flash` and move from `mode: primary` to `mode: all` (usable as subagents by the orchestrator and by `opencode run --agent`). New `rescuer`, `mode: all`, `openai/gpt-6-sol`, `reasoningEffort: high`, same file-only permissions as `worker`. The orchestrator's bash permission mirrors everything `block-unsafe-bash.sh` and `block-secrets.sh` block for Claude, since Claude hooks do not run in opencode: `--no-verify`, `LEFTHOOK=0`, `LEFTHOOK_EXCLUDE`, `core.hooksPath`, `SKIP_REVIEW=1`, shell reads of `.env*` (`cat`/`less`/`head`/`grep`/`source` on dotenv files), the prisma push/reset and `supabase db reset --linked` commands; `tests/` asserts each pattern is denied by opencode's permission evaluation without running the command. Interactive opencode sessions get the LSP tool from `template/mise.toml` `[env] OPENCODE_EXPERIMENTAL_LSP_TOOL = "true"` (today only `opencode.sh` sets it, so only unattended runs have it; needs mise activated in the dev's shell: the README install step gains `mise activate` for bash/zsh/PowerShell). A template `opencode.json` sets `"default_agent": "orchestrator"`, so a plain `opencode` start lands on it (verified by an ordinary start, not only `run --agent`); it is `_skip_if_exists`, and the migration checklist says what to merge into an existing one. | opencode agents as `opencode run` targets only |
| F4 | **Spec and plan review by another vendor, only for substantial work** (anything that gets a spec or a plan under `docs/superpowers/`; never small tasks, never code). Claude Code: a native `Agent` call to the Codex plugin's subagent, `subagent_type: "codex:codex-rescue"`, prompt `--wait` + "Read-only, do not edit. Adversarially review the spec/plan at <path>: assumptions, alternatives, failure modes, migration gaps." The plugin owns the path to its runtime, so nothing of ours breaks when it moves. Output shown to the user as-is; the orchestrator and the user decide what changes; rejected findings get one line under `## Review notes`. Empty result or error (Codex missing, not logged in, quota) → a `general-purpose` subagent on Sonnet with the same review prompt, said in one line. opencode: the orchestrator is OpenAI, so Codex would be the same vendor; plan review goes to the `reviewer` subagent (DeepSeek). | plan review through `opencode.sh reviewer`; the `core:review` skill |
| F5 | **Outside a session, opencode only.** `scripts/review.sh` (pre-push) and `nightly.sh` (server) run `opencode run --agent reviewer|docs` through `scripts/opencode.sh`, which keeps its limit/hang detection, timeout and Windows path fix, minus the backend hand-over. `opencode.sh` ships in the template next to `review.sh`, so a dev without the Claude plugin can push; `review.sh` calls `$here/opencode.sh` and drops the plugin-cache discovery. The nightly ZDR warning becomes unconditional. | runner discovery in `~/.claude/plugins/cache`; `claude.sh` / `codex.sh` runners |
| F6 | **Rescue:** Claude → superpowers `systematic-debugging`, then a fresh `general-purpose` subagent on Sonnet with the problem, failing command and output; opencode → `rescuer` (gpt-6-sol high). Rule unchanged: whoever wrote the code never grades it; verify with `git diff` and the failing command. `/codex:rescue` stays as a manual escalation by the user. | `core:rescue` skill over `worker.sh`; `.claude/agents/rescuer.md` |
| F7 | **Per-dev install:** Claude Code and/or opencode; opencode go ($10, required for the push review); OpenAI login in opencode (opencode orchestrator) and in the Codex CLI + `openai/codex-plugin-cc` plugin (Claude plan review). The codex plugin is always in `enabledPlugins`, review gate off. Server: opencode go only (dedicated account). | per-backend install matrix |
| F8 | **No handoff skill in the plugin.** `core:handoff` deleted; `/adopt` stops calling it; `AGENTS.md` drops the "handoffs arrive as a pasted prompt" line. A dev who wants a handoff asks for it in plain words and the orchestrator writes it as text, or uses whatever personal skill they have installed. `docs/dev/handoffs/` stays: the incident, rollback and restore runbooks log there. | `core:handoff` (v3 E8) |
| F9 | **No skills in the plugin.** Push-blocked handling (read the `[high]` lines, fix, push again, max 3 rounds, never bypass, tell the user `SKIP_REVIEW=1 git push` to type themselves), on-demand `bash scripts/review.sh <base>`, and the F4 rule are a few lines in `template/CLAUDE.md` (opencode: `AGENTS.md`). The plugin keeps hooks, the `doc-keeper` agent, the `/adopt` and `/docs-consolidate` commands and the scripts. | `core:review` skill |
| F10 | **Superpowers integration rules in `CLAUDE.md`.** (a) Superpowers' own spec and plan reviewer (a Claude `general-purpose` subagent in brainstorming and writing-plans) is replaced by F4, so a spec is reviewed once, by another vendor. (b) "Small tasks: no ritual" overrides superpowers' invoke-on-1% rule (project instructions beat skills; superpowers says so itself). (c) Superpowers' worktree skill and the built-in `isolation: "worktree"` are both fine; `.claude/worktrees/` stays gitignored. | two reviewers per spec |

## Layout after v4

```
plugins/core/
  scripts/opencode.sh      # backend hand-over removed; also copied to template/scripts/
  scripts/review.sh        # same file as template/scripts/review.sh
  scripts/nightly.sh       # uses the repo's scripts/opencode.sh
  agents/doc-keeper.md
template/
  .opencode/agents/{orchestrator,worker,rescuer,reviewer,docs}.md
  scripts/{review,opencode}.sh
  opencode.json            # default_agent: orchestrator
```

Deleted: `plugins/core/scripts/{worker,claude,codex}.sh`, `plugins/core/skills/` (all four), `template/.claude/agents/` (all four), `tests/{worker,claude,codex,backend}.test.sh`. Edited: `copier.yml`, `template/{AGENTS,CLAUDE}.md`, `template/.claude/settings.json`, `template/mise.toml`, `deploy/nightly/README.md`, `plugins/core/commands/adopt.md`, `plugins/core/agents/doc-keeper.md` (no change needed), `.claude-plugin/marketplace.json` description, `README.md`, `tests/{opencode,review,nightly}.test.sh`, `CHANGELOG.md`, plugin and marketplace version.

## Migration for adopted repos

Order matters, because the plugin updates for every repo at once while each repo updates on its own:

- Plugin first, repo not yet updated: the repo's old `review.sh` finds the plugin's `opencode.sh`, which no longer hands over to `claude.sh`/`codex.sh`. A `claude`/`codex` repo has no `.opencode/agents/`, so `opencode.sh` exits 3 with `.opencode/agents/reviewer.md missing (run copier update --trust)` and the sensitive push is blocked (fails closed, never approves). `opencode` repos keep working. Old `CLAUDE.md` lines naming `core:worker`/`core:rescue` point at skills that are gone until `/adopt` replaces them; the agent files still work. `nightly.sh` uses the repo's `scripts/opencode.sh` when present, else its own.
- `copier update` removes template files the repo never edited (`.claude/agents/*`); edited copies are listed in the checklist to delete by hand.
- The migration is a tool-neutral checklist in the plugin repo's README ("Upgrading to 0.5.0"): exact sections of `AGENTS.md`/`CLAUDE.md` to replace, `opencode.json` to merge, and a final `grep -rn 'core:worker\|core:rescue\|core:review\|core:handoff\|worker.sh\|backend:' AGENTS.md CLAUDE.md` that must come back empty. Any tool can follow it ("apply the 0.5.0 upgrade from <README url>"); `/adopt` in Claude just points at it.
- Release notes and `/adopt` say: run `copier update --trust` in each repo right after updating the plugin; install opencode go on any dev that was on `claude`/`codex`.
- `copier update --trust`: the stale `backend:` answer is ignored; both agent folders and `scripts/opencode.sh` arrive; `.opencode/agents/` gets the new modes.
- `AGENTS.md`, `CLAUDE.md` and `.claude/settings.json` are `_skip_if_exists`, so copier never rewrites them. `/adopt` on an adopted repo prints the lines to replace (worker/rescue/review sections, `"model": "opus"`, codex plugin entries) and applies them on the user's yes.
- Personal files outside the repo (`~/.agents/AGENTS.md` model table, `~/.claude/CLAUDE.md` worker dispatch line) are the owner's to edit; the release notes list them.

## Risks

- The `codex:codex-rescue` subagent is a forwarder built for rescue tasks; a future plugin version could stop honouring "read-only". Mitigation: the prompt says do not edit, and the orchestrator checks `git status` is unchanged after the review.
- `reasoningEffort` is passed through to the OpenAI provider by opencode; if the OAuth provider ignores it, the orchestrator runs on the provider default. Checked once at implementation with `opencode run --agent orchestrator` and the event log.

## Not doing

- Keeping a Claude → DeepSeek worker path "for cheap bulk work". Re-add as a skill if quota becomes a problem again.
- A Claude-side fallback for the push review (`claude -p`). opencode go is required; a dev without it cannot push sensitive paths until they install it.
- Cross-vendor review of code in session. Push review (DeepSeek) and the night shift cover code.
- A different-vendor **automated** review of DeepSeek-written code on the opencode path. Accepted limit: pre-push and nightly reviewers are DeepSeek, like the opencode worker; the other-model check is the gpt-6-sol orchestrator reading the worker's diff before it commits (F2b). On the Claude path, push review is a different vendor from the author.

## Review notes

Codex adversarial review, 2026-09-24 (verdict needs-attention, 3 findings):
- [high] plugin update breaks unmigrated repos → accepted: migration order section; failure is fail-closed with the fix in the message. Compatibility runners for one release rejected: they are the three-backend matrix we are removing.
- [high] deleting the worker skill drops the isolation and partial-failure contract → accepted: F2b moves it to `AGENTS.md` for both tools; the worker/rescue skills are then redundant and deleted.
- [medium] opencode worker and reviewer are the same model → accepted as a stated limit (Not doing), not fixed.

Codex review via `codex:codex-rescue` (F4 path; read-only held, `git status` unchanged), 2026-09-24 (verdict needs-attention, 4 findings):
- [high] opencode task tool cannot target a worktree → accepted: F2b, parallel opencode workers are separate `opencode run --dir` processes.
- [high] shell-capable opencode orchestrator lacks the Claude hook protections → accepted: F3 mirrors both hooks' patterns in its bash permission, tested.
- [medium] nothing selects the orchestrator → accepted: template `opencode.json` with `default_agent`.
- [medium] migration only runnable from Claude → accepted: tool-neutral README checklist with a grep that must come back empty.
