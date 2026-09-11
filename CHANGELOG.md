# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/). Versioning: SemVer.

## [Unreleased]

### Changed

- `core` plugin bumped to 0.1.3.
- `lefthook.yml` template: `pre-push` semgrep step now runs `--config p/default` instead of `--config auto` (the `auto` ruleset requires metrics, which the gate runs with `--metrics=off`).
- `lefthook.yml` template: `pre-push` trivy step now skips `.env*` files (`--skip-files ".env*,**/.env*"`) so local env files with placeholder-looking values don't fail the secret scan.

### Fixed

- `handoff` skill: templates and adopt now reference it as `core:handoff`. The bare name `handoff` collided with `mattpocock-skills:handoff` (`disable-model-invocation: true`), so the model got "cannot be used with Skill tool" when it tried to run ours.
- `codex-review` skill: calls `codex-companion.mjs adversarial-review` directly instead of `/codex:adversarial-review`, which is a user-only command (`disable-model-invocation: true`) and failed with "only the user can run it" when the skill ran.
- `design-lint.sh`: when lefthook passes an explicit staged file list, the script now checks only the newly added/changed lines of the diff instead of the whole file, so touching a file for an unrelated reason no longer resurfaces pre-existing hardcoded-value violations elsewhere in it. A full repo scan (no file args) still checks whole file contents.
- `design-lint.sh`: `src/components/ui/*` (the vendored primitives/token source) is now exempt from the check, same as `globals.css`.
- `design-lint.sh`: bracket values that are pure CSS custom-property references (`-[var(--x)]`, `-[--x]`) are masked before matching, so a token reference no longer trips the hardcoded-value check — while other hardcoded values on the same line (e.g. a `#hex` fallback) are still caught.
