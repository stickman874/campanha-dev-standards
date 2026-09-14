# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/). Versioning: SemVer.

## [Unreleased]

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
