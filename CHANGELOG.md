# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/). Versioning: SemVer.

## [Unreleased]

## [0.5.5] - 2026-09-26

### Changed
- Settings template enables only core, superpowers, typescript-lsp and codex. Dropped security-guidance (11 hooks), commit-commands, playwright (use the Playwright CLI) and impeccable (turn it on per project for UI work). Why and the measurements: `docs/superpowers/research/2026-09-26-slowness-and-slim-down.md`.
- `/adopt`: existing repos copy the template's `enabledPlugins` block and drop the four plugins above.
- The opencode worker contract moved from `AGENTS.md` (`## opencode`) to `.opencode/agents/orchestrator.md` (`## Subagents`): only the opencode orchestrator uses it, and Claude Code no longer loads ~1.8 KB of it every session.

### Upgrading
- `copier update --trust` does not touch `.claude/`: in each adopted repo, edit `.claude/settings.json` by hand to match the template's `enabledPlugins`.
- `copier update --trust` refreshes `.opencode/agents/orchestrator.md`; then delete the `## opencode` section from your `AGENTS.md` by hand (copier never rewrites it) and point the `## Models` opencode line at the orchestrator file.

## [0.5.4] - 2026-09-25

### Security
- `review.sh`: each run sends the reviewer a random nonce and only accepts a verdict object that carries it, so a verdict planted in the diff can no longer approve a push.
- `review.sh`: `.review-paths` and `.copier-answers.yml` count as sensitive, so weakening the extra paths is itself reviewed.

### Known limits (documented)
- opencode's `grep` tool permission matches the search pattern, not the file: an explicit `.env` path is still searchable. Normal searches skip gitignored `.env` files. The orchestrator's bash reader list is best-effort.

## [0.5.3] - 2026-09-25

### Security
- `review.sh`: an invalid regex in `.review-paths` made grep fail and the push was treated as routine (unreviewed); it now blocks with "invalid regex in .review-paths".
- `review.sh`: a reply with two different verdict objects (e.g. a fake approve copied from the diff) blocks; the diff is fenced in the prompt as untrusted data.

### Changed
- `review.sh`: reviewer timeout default 600 s (large diffs timed out at 300 s).

## [0.5.2] - 2026-09-25

### Changed
- Claude Code subagents default to Sonnet (`CLAUDE_CODE_SUBAGENT_MODEL`, `CLAUDE.md` delegation line): Haiku 4.5 needed more correction rounds and cost more per finished task in real use. Revisit when Haiku 5.5 ships.

### Fixed
- `review.sh` is stored with LF endings again; `.gitattributes` pins `*.sh` to LF.

## [0.5.1] - 2026-09-25

### Fixed
- `review.sh`: the verdict JSON is now the LAST balanced-brace object in the reviewer's reply that has a `verdict` key, so stray braces in prose (e.g. a literal `{push_files}`) before the real answer no longer fool the parser into "no valid JSON verdict, blocked".
- Claude hook `block-unsafe-bash.sh`: `core.hooksPath` check is now case-insensitive (`CORE.HOOKSPATH` was slipping through); short no-verify commit flags (`-n`, clusters like `-an`) are denied without touching a lone `-m`; force pushes (`--force`, `--force-with-lease`, ` -f`, `+refspec`) and pushes to a `prod`-named ref are denied. Quoted commit messages mentioning these words stay allowed.

### Security
- `review.sh`: severity comparison is now case-insensitive — any finding whose lowercased severity is not `low` or `medium` (`High`, `CRITICAL`, unknown values) blocks the push.
- `review.sh`: `AGENTS.md` and `CLAUDE.md` added to the built-in sensitive paths.
- `review.sh`: diffs larger than `REVIEW_MAX_BYTES` (default 300000 bytes) are refused before ever reaching the reviewer ("push in smaller ranges") instead of being sent whole.
- opencode agents (`orchestrator`, `worker`, `rescuer`, `reviewer`, `docs`): the `read` tool now denies `.env`/`.env.*` (opencode's own default is "ask", which `--auto` auto-approves); `.env.example` stays readable.
- opencode `orchestrator` bash permission: added denies for short/typo `--no-verify` forms on `git commit`, case variants of `core.hooksPath`, force pushes, pushes to `prod`-named refs, and reading `.env` through `tac`/`sort`/`uniq`/`strings`/`od`/`xxd`/`base64`/`nl`/`find`.

### Added
- `review.sh`: per-repo extra sensitive paths via an optional `.review-paths` file at the repo root (one extended-regex pattern per line, OR-ed into the built-in list). Not shipped by the template.

### Changed
- No backends: the copier `backend` question is gone. Claude Code runs on superpowers plus built-in subagents (Opus orchestrator); opencode runs on `.opencode/agents/` with a new `orchestrator` (gpt-6-sol, medium, default agent via `opencode.json`) and a new `rescuer` (gpt-6-sol, high); `worker`, `reviewer` and `docs` are `mode: all`.
- `scripts/opencode.sh` ships in the template next to `review.sh`; `review.sh` no longer searches the Claude plugin cache. The night shift prefers the repo's runner and checks the ZDR date for every repo.
- Specs and plans are reviewed by another vendor: Codex through the `codex:codex-rescue` subagent on Claude Code, the DeepSeek `reviewer` on opencode.
- `AGENTS.md`: `## Parallel work` (parallelise as much as possible) and the `## opencode` worker contract. `mise.toml` sets `OPENCODE_EXPERIMENTAL_LSP_TOOL` for interactive opencode sessions.

### Removed
- Skills `core:worker`, `core:rescue`, `core:review`, `core:handoff`; runners `worker.sh`, `claude.sh`, `codex.sh`; `template/.claude/agents/`.

### Security
- The opencode `orchestrator`'s bash permission denies what the Claude hooks deny (gate bypasses, dotenv reads, destructive database commands, token shapes), tested against opencode's own permission check.

## [0.4.0] - 2026-09-24

### Added
- Codex backend: copier `backend: codex`. Claude (Opus) orchestrates; worker and rescue call the Codex plugin's `codex:codex-rescue` subagent with `--model gpt-6-sol`; review and night shift use the new runner `scripts/codex.sh` (`codex exec`, instructions from `.claude/agents/<agent>.md`, reviewer read-only, exit 3 `CODEX_UNAVAILABLE`, model `CODEX_MODEL`). The docs agent stays on Haiku through `claude.sh`. Windows needs `[windows] sandbox = "unelevated"` in `~/.codex/config.toml`. Codex has no dotenv deny rule, so the reviewer runs in a throwaway `git worktree` at HEAD (no untracked `.env` there); worker and rescue rely on the prompt. `core:worker` documents how to kill the Codex plugin's orphaned broker that locks a worktree on Windows.
- Claude-only backend: copier question `backend` (`opencode` default, or `claude`). On `claude` the repo gets `.claude/agents/{worker,rescuer,reviewer,docs}.md` (worker and docs on Haiku, reviewer and rescuer on Sonnet, no shell) instead of `.opencode/`, no Codex plugin, and orchestrator `opus`. `core:worker` and `core:rescue` call `worker` / `rescuer` as native subagents. Review and night shift run outside a session, so they use the new runner `scripts/claude.sh` (`claude -p --agent`, no MCP, same contract as `opencode.sh`, exit 3 `CLAUDE_UNAVAILABLE`); `opencode.sh` hands over to it when `.copier-answers.yml` says `backend: claude` (or `CAMPANHA_BACKEND=claude`).

### Fixed
- `core:worker`: workers never commit, so the caller commits inside each parallel worktree before cherry-picking; copier appends `.claude/worktrees/` to the repo's `.gitignore`.

## [0.3.2] - 2026-09-22

### Added
- `core:worker`: parallel workers via one `git worktree` per task; the clean-tree rule holds per worktree, so each diff stays attributable.

## [0.3.1] - 2026-09-16

### Added
- UI component sourcing rule: shadcn standard (Base UI) first; ReUI via its MCP (`https://mcp.reui.io/api/mcp`) + `reui` skill only when shadcn has nothing that fits; never hand-roll what a registry ships. In `template/AGENTS.md`, `template/.claude/rules/frontend.md`, `template/DESIGN.md`, new `template/docs/dev/how-to/ui-components.md`. Global install: `REUI_GLOBAL=1 curl -fsSL https://mcp.reui.io/install | node -` (Claude + Codex), opencode by hand (README).

### Fixed

- `nightly.sh`: review timeout 1500 s at night (a first run over dozens of commits needs it); the last-reviewed sha advances once the report is pushed even when a step failed, so a giant first range cannot wedge the job; no more EPIPE noise from `printf | head`.
- `review.sh`: `actions.ts` server-action files count as sensitive (the pattern required `/actions/`). Found by the DeepSeek reviewer on its first real push.
- `review.sh`: a remote sha not present locally (branch behind origin) no longer fails with "cannot diff"; the range falls back to the merge-base like a new branch.

## [0.3.0] - 2026-09-15

### Added
- `scripts/opencode.sh`: one runner for every unattended opencode call (`run --format json`), usage/auth/error/timeout detection, event log.
- `scripts/review.sh` + `reviewer` agent (read-only DeepSeek on opencode go): JSON findings, blocks on `block`, any `high`, invalid JSON or unavailable reviewer; `SKIP_REVIEW=1` for humans, logged.
- `scripts/nightly.sh` + `docs` agent + `deploy/nightly/`: night shift on the server (semgrep, trivy, Socket, full review, docs refresh) → `nightly/<date>` branch and `docs/dev/reviews/<date>.md`; ZDR reminder every 35 days.
- `core:rescue` skill.
- `worker.sh` exit 4 (wrote nothing) and claimed-vs-real file cross-check.
### Changed
- Push gates: typecheck, tests, sensitive-path review only (spec E3). semgrep, trivy and docs-check moved to the night shift.
- `core:handoff` prints a paste-ready prompt; a file only on request.
- `block-unsafe-bash.sh` denies `SKIP_REVIEW=1`/`LEFTHOOK=0`/`LEFTHOOK_EXCLUDE` and anchors bypass rules to git commands (no more false positives on quoted text).
- `deepseek-worker` agent renamed `worker`; never asks for `.env` (no shell).
- `CLAUDE.md` template: zero ritual on small tasks.
### Removed
- `codex-review.sh`, `codex-review` skill, Codex CLI from `mise.toml` (Codex optional, plan quota too small for a push gate).
- `docs-check.sh` (night shift refreshes docs instead of blocking pushes).

## [0.2.0] - 2026-09-15

### Added

- `scripts/codex-review.sh`: pre-push Codex review, model by diff sensitivity, `VERDICT` gate, `CODEX_REVIEW_MODEL`/`CODEX_REVIEW_EFFORT` overrides.
- `scripts/docs-check.sh`: push blocked when code changed without `docs/` or `CHANGELOG`.
- `scripts/worker.sh` + `core:worker` skill.
- `template/mise.toml`.
- Copier template (`copier.yml`, `copier update` re-sync, `.copier-answers.yml`).
- `docs/dev/how-to/design-lint.md`.
- Settings template enables sandbox, security-guidance, commit-commands, typescript-lsp.
- The opencode worker agent ships in each project at `.opencode/agents/`.

### Changed

- Enforcement moved from a Claude-only push gate to lefthook `pre-push` (humans and agents alike).
- Codex called with `gpt-5.6-sol`/medium by default and `gpt-6-astra`/medium for sensitive paths instead of the global astra/low.
- gitleaks pre-commit uses `gitleaks git --pre-commit --staged` (`protect` is deprecated).
- trivy adds `--ignore-unfixed --skip-dirs node_modules`.
- `doc-keeper` mode push renamed `diff`, no marker files.
- Docs tree pruned (no `docs/product/manual`, `docs/dev/{specs,plans,research}`; adopt report now `docs/dev/decisions/0001-adopt-report.md`).
- Skill `deepseek-worker` renamed `worker`.
- Templates moved to `template/` with Jinja placeholders.
- `/adopt` now runs copier + mise + lefthook.
- `block-unsafe-bash.sh` also denies `core.hooksPath` and `LEFTHOOK=0` bypasses; its dotenv rule now fires only on read commands (quoted or not), not on any mention of the file, and stays as belt and braces for repos whose `.claude/settings.json` predates the sandbox.

### Removed

- `pre-push-gate.sh` and `.git/campanha` marker files.
- opencode `guard.js` (opencode permission defaults cover dotenv reads; the sandbox covers Claude).
- `deepseek.sh` review mode, test loop, redaction and the `deepseek-reviewer` agent (the orchestrator runs tests; Codex reviews every push).
- `Worker: deepseek` trailer.
- `security-posture` skill (official `security-guidance` plugin).
- `design-lint.sh` (eslint plugin).
- `install.sh` (mise).
- `adopt.sh` (copier).
- Eight wording-only test files.

The `[Unreleased]` entries of 0.1.5 (`deepseek.sh` `Test:` loop, DeepSeek reviewer routing, guard agent links) were never released and are superseded by this version.

## [0.1.4] - 2026-09-14

### Added

- `/adopt` enables the official Claude Code LSP plugin for each detected stack (`package.json`/`tsconfig.json` → `typescript-lsp`, `pyproject.toml` → `pyright-lsp`, `go.mod` → `gopls-lsp`, Rust, PHP, C#, Java, Swift, C/C++) in the project's `.claude/settings.json`, and flags a missing language-server binary as `needs-review`. `install.sh` installs `typescript-language-server`.
- `AGENTS.md` template: `## Code navigation` — prefer the LSP tool (`workspaceSymbol`, `findReferences`, `goToDefinition`/`goToImplementation`, `hover`) over grep/whole-file reads; grep only for plain text; fix diagnostics before moving on. Same operation names in Claude Code and opencode.
- `core:deepseek-worker` agent: relays a scoped edit/search task to DeepSeek V4.1 Flash via `opencode run --agent deepseek-worker` (opencode agent shipped in `plugins/core/opencode/agents/`, `bash` and `task` denied, linked by `install.sh`; the task goes through a quoted heredoc so it is never shell-expanded); returns `DEEPSEEK_UNAVAILABLE` on missing opencode or missing core guard (never runs `--auto` ungated), usage/rate limit, auth error or timeout (opencode retries limits silently and never exits) so Claude falls back to Sonnet. Templates `AGENTS.md` (new `## Models`) and `CLAUDE.md`, and the design spec, now name DeepSeek-if-available-else-Sonnet as the worker standard.
- `plugins/core/opencode/guard.js`: opencode plugin that runs `block-secrets.sh`, `block-unsafe-bash.sh` and `pre-push-gate.sh` before opencode's `bash` tool, so opencode sessions and `opencode run --auto` workers (e.g. DeepSeek) hit the same gates as Claude. Rules stay only in `hooks/*.sh`; a hook that cannot run blocks the command. `install.sh` symlinks it into `~/.config/opencode/plugins/` when opencode is installed. It also blocks opencode's native file tools (`read`, `edit`, `grep`, …) on `.env`/`.env.*` (not `.env.example`), matching the Claude settings deny list, including `grep` include globs, `apply_patch` targets (add/delete/update/move) and symlinks that resolve to a secret file; matches from secret files in broad `grep` results are redacted. It is a guardrail, not a sandbox — hence the unattended worker agent has no shell.

### Changed

- `AGENTS.md` template: new `## Communication` section (answer in the language asked, plain IT-not-programmer register, concise/token-saving, option selector with a `(recommended)` choice) so team comms defaults reach both Claude and Codex on adopt.
- README: optional personal-preferences snippet to paste into `~/.claude/CLAUDE.md` for the same defaults globally per dev.
- `core` plugin bumped to 0.1.4.
- `lefthook.yml` template: `pre-push` semgrep step now runs `--config p/default` instead of `--config auto` (the `auto` ruleset requires metrics, which the gate runs with `--metrics=off`).
- `lefthook.yml` template: `pre-push` trivy step now skips `.env*` files (`--skip-files ".env*,**/.env*"`) so local env files with placeholder-looking values don't fail the secret scan.

### Fixed

- `block-unsafe-bash.sh`: `.env` files behind a directory (`cat deploy/.env.secrets`, `./.env`, `/srv/app/.env`) were not blocked because `/` was excluded before `.env`; now denied, `.env.example` still allowed.
- `handoff` skill: templates and adopt now reference it as `core:handoff`. The bare name `handoff` collided with `mattpocock-skills:handoff` (`disable-model-invocation: true`), so the model got "cannot be used with Skill tool" when it tried to run ours.
- `codex-review` skill: calls `codex-companion.mjs adversarial-review` directly instead of `/codex:adversarial-review`, which is a user-only command (`disable-model-invocation: true`) and failed with "only the user can run it" when the skill ran. The runtime path is now resolved from `~/.claude/plugins/installed_plugins.json`, preferring this project's own install over the user-scope one, so a pinned/rolled-back Codex version is honoured instead of always picking the newest cached install.
- `design-lint.sh`: when lefthook passes an explicit staged file list, the script now checks only the newly added/changed lines of the diff instead of the whole file, so touching a file for an unrelated reason no longer resurfaces pre-existing hardcoded-value violations elsewhere in it. A full repo scan (no file args) still checks whole file contents.
- `design-lint.sh`: `src/components/ui/*` (the vendored primitives/token source) is now exempt from the check, same as `globals.css`.
- `design-lint.sh`: bracket values that are pure CSS custom-property references (`-[var(--x)]`, `-[--x]`) are masked before matching, so a token reference no longer trips the hardcoded-value check — while other hardcoded values on the same line (e.g. a `#hex` fallback) are still caught.
