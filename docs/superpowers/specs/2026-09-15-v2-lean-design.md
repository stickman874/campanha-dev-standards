# campanha-dev-standards v2 — lean design

Date: 2026-09-15 · Status: approved by owner (conversation 2026-09-15) · Supersedes the enforcement, worker and distribution sections of `2026-09-10-campanha-dev-standards-design.md`; the documentation tree and conventions sections stay.

## Why

The 2026-09-15 review found ~1,900 lines of custom code doing what native features, official plugins or maintained tools already do, and three custom layers (push-gate markers, opencode guard, DeepSeek test/review pipeline) that each needed their own tests and docs. Goal of v2: same three outcomes (uniformity, cheap gruntwork, living docs) with ~10 config files and 3 small scripts.

## Decisions

| # | Decision | Replaces |
|---|---|---|
| D1 | **Enforcement lives in lefthook `pre-push`, for humans and agents alike.** Codex adversarial review runs inside the hook (`codex exec -s read-only`, since `codex review --base` rejects a custom prompt). No markers, no Claude-only push gate. No CI service (owner declined GitHub Actions). | `pre-push-gate.sh`, `.git/campanha/*` markers, marker carry-forward in doc-keeper |
| D2 | **Codex model per diff:** `gpt-5.6-sol` + `medium` for routine diffs; `gpt-6-astra` + `medium` when the diff touches auth, payments, API handlers, migrations or the gates. Set with `-c`, never by changing `~/.codex/config.toml`. | astra+low for everything |
| D3 | **Docs are enforced by content, not markers:** `docs-check.sh` fails the push when code paths changed and neither `docs/` nor `CHANGELOG.md` did. Fix = run the `doc-keeper` agent or edit by hand. | docs marker |
| D4 | **DeepSeek stays the worker, without a pipeline.** `worker.sh` (~35 lines): clean-tree check, `opencode run --agent deepseek-worker --auto`, rate-limit watch, timeout, `git status`. No `Test:` line, no test run, no correction round inside the script, no DeepSeek reviewer, no `Worker:` trailer. The orchestrator runs the relevant test file itself (one command) and decides on one correction round. LSP tool enabled for the worker (`OPENCODE_EXPERIMENTAL_LSP_TOOL=true`). | `deepseek.sh` run/review modes, `deepseek-reviewer` agent, test loop, redaction |
| D5 | **The opencode agent ships in the project** at `.opencode/agents/deepseek-worker.md` via the template; opencode reads project-level agents. Nothing is symlinked into `~/.config/opencode`. | `install.sh` linking, `guard.js` |
| D6 | **Secrets:** Claude Code `sandbox.enabled` + `permissions.deny` for `.env*`; opencode's default `permission.read` already denies `*.env`/`*.env.*`. One hook remains for what nothing native does: `--no-verify`, `core.hooksPath`, `LEFTHOOK=0`, `prisma db push/reset`, `supabase db reset --linked`, plus a dotenv *read* rule (anchored to read commands, quoted or not) kept for repos whose settings predate the sandbox (Codex review finding). `block-secrets.sh` (secret shapes in command text) stays as-is. | `.env` regex in `block-unsafe-bash.sh`, `guard.js` |
| D7 | **Security judgment** comes from the official `security-guidance` plugin (enabled in the settings template) plus Codex review. | `security-posture` skill |
| D8 | **Design lint** is `eslint-plugin-better-tailwindcss` in the project's eslint config (documented in `docs/dev/how-to/design-lint.md`), run by the existing `lint` pre-commit step. | `design-lint.sh` |
| D9 | **Binaries via `mise.toml`** in the template (lefthook, gitleaks, semgrep, trivy, jq, node, `npm:@openai/codex`, `pipx:copier`). | `install.sh` |
| D10 | **Templates via copier.** `copier copy gh:stickman874/campanha-dev-standards .` creates; `copier update` re-syncs. `_skip_if_exists` protects human-edited files (AGENTS.md, docs/**, README, CHANGELOG, DESIGN.md, SECURITY.md, `.claude/settings.json`, `.claude/rules/**`; existing repos merge new settings such as `sandbox` by hand, see `/adopt`). `/adopt` becomes: copier + `mise install` + `lefthook install` + a doc-migration prompt for existing repos. | `adopt.sh`, `{{PROJECT}}` sed |
| D11 | **Docs tree pruned:** drop `docs/product/manual/`, `docs/dev/research/`, `docs/dev/plans/`, `docs/dev/specs/` (superpowers writes to `docs/superpowers/`). Keep `architecture.md`, `decisions/`, `how-to/`, `reference/`, `explanation/`, `handoffs/`, `docs/product/{features,roles.md,glossary.md}`. | — |
| D12 | **Tests test behaviour only:** one test file per script (`hooks-bash`, `worker`, `codex-review`, `docs-check`, `e2e`), plus `bash -n` and frontmatter parse for Markdown assets. No "file contains phrase" tests. | 8 wording tests |
| D13 | `gitleaks git --pre-commit --staged` replaces the deprecated `gitleaks protect`. trivy gets `--ignore-unfixed --skip-dirs node_modules`. | — |

## Layout after v2

```
.claude-plugin/marketplace.json
copier.yml                                  # questions: project_name, tenant; _subdirectory: template
template/                                   # rendered by copier (was plugins/core/templates)
  AGENTS.md CLAUDE.md README.md CHANGELOG.md SECURITY.md DESIGN.md lefthook.yml mise.toml
  .claude/settings.json .claude/rules/{api,database,frontend}.md
  .opencode/agents/deepseek-worker.md
  scripts/codex-review.sh scripts/docs-check.sh
  public/.well-known/security.txt
  docs/dev/{architecture.md,decisions/0000-template.md,how-to/*,reference/*,explanation/security.md,handoffs/.gitkeep}
  docs/product/{roles.md,glossary.md,features/.gitkeep}
plugins/core/
  .claude-plugin/plugin.json                # 0.2.0
  hooks/hooks.json hooks/block-secrets.sh hooks/block-unsafe-bash.sh
  agents/doc-keeper.md                      # modes: diff, consolidate
  skills/{worker,codex-review,handoff}/SKILL.md
  commands/{adopt,docs-consolidate}.md
  scripts/worker.sh
tests/{run.sh,lib.sh,hooks-bash,worker,codex-review,docs-check,assets,e2e}.test.sh
```

## Accepted limitations

- Hooks are guardrails: `git config core.hooksPath` is denied for Claude, but a human can bypass anything locally. Accepted; there is no server-side gate by choice.
- `codex review` output is free text; the script asks for a fixed `VERDICT:` line and blocks on `VERDICT: block`. If the model ignores the format, the push is blocked (fail closed) and the output is shown.
- Every push costs one Codex review. The `AGENTS.md` rule "push per unit of work, not per commit" limits it.
