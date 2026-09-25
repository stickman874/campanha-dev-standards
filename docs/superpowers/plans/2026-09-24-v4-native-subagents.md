# v4 Native Subagents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Release 0.5.0: remove the three-backend matrix; Claude Code runs on superpowers + built-in subagents, opencode runs on its own `.opencode/agents/` with a gpt-6-sol orchestrator, and only the push review and night shift run outside a session (opencode).

**Architecture:** Delete the Claude→opencode runners and skills; keep `opencode.sh` as the one unattended runner, shipped in the template next to `review.sh`; add `orchestrator`/`rescuer` opencode agents with the Claude hooks' guards mirrored as opencode bash permissions; move all process rules into `AGENTS.md` (shared + `## opencode`) and `CLAUDE.md` (Claude-only).

**Tech Stack:** bash (Git Bash on Windows, Linux, macOS), jq, copier 9, opencode 1.18+, lefthook, Claude Code plugin format.

**Spec:** `docs/superpowers/specs/2026-09-24-v4-native-subagents-design.md`

## Global Constraints

- Scripts are plain bash and must run unchanged in Git Bash (Windows), Linux and macOS.
- Tests use `tests/lib.sh` (`assert_eq`, `assert_contains`, `assert_exit`, `finish`); run all with `bash tests/run.sh`, one with `bash tests/<name>.test.sh`, from the repo root.
- `template/scripts/review.sh` ≡ `plugins/core/scripts/review.sh` and `template/scripts/opencode.sh` ≡ `plugins/core/scripts/opencode.sh`, byte for byte.
- `.opencode/agents/*.md` at the repo root ≡ `template/.opencode/agents/*.md` (this repo dogfoods them).
- Models: `orchestrator` → `openai/gpt-6-sol`, `reasoningEffort: medium`, `mode: primary`; `rescuer` → `openai/gpt-6-sol`, `reasoningEffort: high`, `mode: all`; `worker`, `reviewer`, `docs` → `opencode-go/deepseek-v4.1-flash`, `mode: all`.
- The only Jinja left in the template is `{{ project_name }}`, `{{ tenant }}` and `.copier-answers.yml`.
- Docs, comments, commit messages in English. Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Claude's own PreToolUse hooks deny any Bash command whose text contains a gate bypass, a dotenv read, `prisma db push`/`migrate reset`, `supabase db reset --linked` or a token shape.** Those strings may live in files (tests, agent frontmatter) but never in a command you type. Put them in files, then run the file.
- Version `0.5.0` in `plugins/core/.claude-plugin/plugin.json`.

## Review Focus

- A repo not yet migrated (`backend: claude` in `.copier-answers.yml`, no `.opencode/agents/`) after the plugin updates: the push review must fail closed with "run copier update --trust", never approve. → Task 1 test.
- A stale `backend: claude` answer or `CAMPANHA_BACKEND=claude` must no longer divert `opencode.sh`. → Task 1 test.
- Night shift on a server checkout that predates 0.5.0 (no `scripts/opencode.sh` in the repo) must fall back to the plugin's runner; a migrated repo must use its own. → Task 3 test.
- The opencode orchestrator must deny compound and prefixed bypasses (`cd app && git push … --no-verify`, `env SKIP_REVIEW=1 …`, `command git …`) exactly like the Claude hook. → Task 4 test.
- A shell command naming `.env.example` next to a real dotenv file (`cat .env.local .env.example`) must be denied. opencode matches whole-command wildcards with the last matching rule winning, so there are no `.env.example` carve-outs: the orchestrator reads `.env.example` with the read tool (allowed by opencode's defaults), never the shell. → Task 4 test.

---

### Task 1: One runner, no backend hand-over

**Files:**
- Modify: `plugins/core/scripts/opencode.sh`
- Create: `template/scripts/opencode.sh` (copy of the plugin file)
- Modify: `tests/opencode.test.sh`
- Delete: `plugins/core/scripts/worker.sh`, `plugins/core/scripts/claude.sh`, `plugins/core/scripts/codex.sh`, `tests/worker.test.sh`, `tests/claude.test.sh`, `tests/codex.test.sh`

**Interfaces:**
- Produces: `opencode.sh <repo> <agent> < prompt` — same contract as today (stdout final text; exit 0 / 2 usage / 3 `DEEPSEEK_UNAVAILABLE: <why>`), never reads `.copier-answers.yml`. Missing agent file message: `.opencode/agents/<agent>.md missing in the project (run copier update --trust)`.

- [ ] **Step 1: Write the failing tests** — append before the final `rm -rf "$W"; finish` line of `tests/opencode.test.sh`:

```bash
# 0.5.0: no backends — a stale answer or env var never diverts the runner
printf 'backend: claude\n' > "$W/repo/.copier-answers.yml"
out=$(echo x | run ok "$W/repo" worker 2>/dev/null); assert_eq "Summary: done" "$out" "stale backend answer ignored"
rm "$W/repo/.copier-answers.yml"
out=$(echo x | CAMPANHA_BACKEND=claude run ok "$W/repo" worker 2>/dev/null); assert_eq "Summary: done" "$out" "CAMPANHA_BACKEND ignored"
out=$(echo x | run ok "$W/repo" reviewer 2>/dev/null); assert_contains "$out" 'run copier update --trust' "missing agent names the upgrade command"
cmp -s plugins/core/scripts/opencode.sh template/scripts/opencode.sh && echo "  ok  template and plugin opencode.sh identical" || { echo "  FAIL opencode.sh copies differ"; FAILS=$((FAILS+1)); }   # tests run from the repo root
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/opencode.test.sh`
Expected: `FAIL stale backend answer ignored`, `FAIL CAMPANHA_BACKEND ignored`, `FAIL missing agent names the upgrade command`, `FAIL opencode.sh copies differ`.

- [ ] **Step 3: Implement** — in `plugins/core/scripts/opencode.sh`:
  - Line 3: `# Runs one project opencode agent unattended and returns its final text. Shared by review.sh and nightly.sh.`
  - Delete lines 7–8 (the two `# Backend: …` comment lines).
  - Delete the `backend=…` assignment and the whole `case $backend in … esac` block (lines 13–18).
  - Change the agent-file check to:

```bash
[ -f "$repo/.opencode/agents/$agent.md" ] || unavailable ".opencode/agents/$agent.md missing in the project (run copier update --trust)"
```

  Then: `cp plugins/core/scripts/opencode.sh template/scripts/opencode.sh`
  Then: `git rm -q plugins/core/scripts/worker.sh plugins/core/scripts/claude.sh plugins/core/scripts/codex.sh tests/worker.test.sh tests/claude.test.sh tests/codex.test.sh`

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/opencode.test.sh`
Expected: all `ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/core/scripts template/scripts/opencode.sh tests
git commit -m "refactor(runner): opencode.sh is the only runner; drop claude/codex/worker scripts"
```

---

### Task 2: review.sh uses the runner next to it

**Files:**
- Modify: `template/scripts/review.sh`, then copy to `plugins/core/scripts/review.sh`
- Modify: `tests/review.test.sh`

**Interfaces:**
- Consumes: `template/scripts/opencode.sh` (Task 1).
- Produces: `review.sh` resolves its runner as `${OPENCODE_SH:-$here/opencode.sh}`; when missing, exits 1 with `review: <path> not found (run copier update --trust)`.

- [ ] **Step 1: Write the failing test** — in `tests/review.test.sh`, add after line 3 (`S=…`): `O=$PWD/template/scripts/opencode.sh`. Replace the block from `# runner discovery: real cache layout …` through its `rm -rf "$W2"` with:

```bash
# runner: the opencode.sh next to review.sh (the template ships both); no plugin cache lookup
W2=$(mktemp -d); mkdir -p "$W2/scripts"; cp "$S" "$O" "$W2/scripts/"
out=$(env -u OPENCODE_SH -u CLAUDE_PLUGIN_ROOT HOME="$W2" FAKE_MODE=approve bash "$W2/scripts/review.sh" base 2>&1); code=$?
assert_eq 0 "$code" "uses the opencode.sh next to it"
rm "$W2/scripts/opencode.sh"
out=$(env -u OPENCODE_SH -u CLAUDE_PLUGIN_ROOT HOME="$W2" FAKE_MODE=approve bash "$W2/scripts/review.sh" base 2>&1); code=$?
assert_eq 1 "$code" "no runner next to it: blocks"; assert_contains "$out" 'run copier update --trust' "names the upgrade command"
rm -rf "$W2"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/review.test.sh`
Expected: `FAIL names the upgrade command`.

- [ ] **Step 3: Implement** — in `template/scripts/review.sh`:
  - Line 2: `# Adversarial review of pushed ranges by the project's read-only `reviewer` agent (DeepSeek on opencode go, via the opencode.sh next to this file).`
  - Replace lines 9–17 (from `here=` through the closing `fi` of the discovery) with:

```bash
here=$(cd "$(dirname "$0")" && pwd)
runner=${OPENCODE_SH:-$here/opencode.sh}
```

  - Replace the `[ -f "$runner" ] || …` line with:

```bash
  [ -f "$runner" ] || { echo "review: $runner not found (run copier update --trust)" >&2; exit 1; }
```

  Then: `cp template/scripts/review.sh plugins/core/scripts/review.sh`

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/review.test.sh`
Expected: all `ok` (including `template and plugin review.sh identical`).

- [ ] **Step 5: Commit**

```bash
git add template/scripts/review.sh plugins/core/scripts/review.sh tests/review.test.sh
git commit -m "refactor(review): run the opencode.sh shipped next to review.sh"
```

---

### Task 3: Night shift picks the repo's runner; ZDR check always on

**Files:**
- Modify: `plugins/core/scripts/nightly.sh`
- Modify: `tests/nightly.test.sh`
- Modify: `deploy/nightly/README.md`

**Interfaces:**
- Consumes: `opencode.sh` contract (Task 1); `review.sh` honours `OPENCODE_SH` (Task 2).
- Produces: runner precedence `OPENCODE_SH` env → `<repo>/scripts/opencode.sh` (after checkout) → `<plugin>/scripts/opencode.sh`; exported as `OPENCODE_SH` for `review.sh`.

- [ ] **Step 1: Write the failing tests** in `tests/nightly.test.sh`:
  - In the initial fixture (the line that writes `docs/dev/architecture.md`), also write a stale answer: add `printf 'backend: claude\n' > .copier-answers.yml` before `git add -A`. The existing `ZDR warning when never confirmed` assertion now covers "warning is unconditional".
  - Insert before the line `git checkout -q main; echo e >> src/a.ts; git rm -q scripts/review.sh; …`:

```bash
# runner: plugin's own when the repo predates 0.5.0, the repo's scripts/opencode.sh once it ships one
git checkout -q main; echo f >> src/a.ts; git commit -qam f; git push -q origin main
out=$(env -u OPENCODE_SH bash "$S" "$W/repo" 2>&1); code=$?
assert_eq 0 "$code" "no repo runner: falls back to the plugin's"
export MARK="$W/mark" REAL="$OLDPWD/plugins/core/scripts/opencode.sh"
git checkout -q main; printf '#!/usr/bin/env bash\ntouch "$MARK"; exec bash "$REAL" "$@"\n' > scripts/opencode.sh; echo g >> src/a.ts; git add -A; git commit -qm g; git push -q origin main
rm -f "$MARK"; out=$(env -u OPENCODE_SH bash "$S" "$W/repo" 2>&1); code=$?
assert_eq 0 "$code" "repo runner run exits 0"
[ -e "$MARK" ] && echo "  ok  repo's scripts/opencode.sh used" || { echo "  FAIL repo runner not used"; FAILS=$((FAILS+1)); }
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/nightly.test.sh`
Expected: `FAIL repo runner not used` (and, before Task 1 lands, the ZDR assertion).

- [ ] **Step 3: Implement** — in `plugins/core/scripts/nightly.sh`:
  - Line 3: `#   nightly.sh <repo>   needs: git with push rights, opencode login (dedicated opencode go account), semgrep, trivy, npx (Socket), jq.`
  - Line 10 becomes: `here=$(cd "$(dirname "$0")" && pwd)`
  - After the `git fetch … || { … exit 1; }` line add:

```bash
[ -n "${OPENCODE_SH:-}" ] || { if [ -f scripts/opencode.sh ]; then OPENCODE_SH=$PWD/scripts/opencode.sh; else OPENCODE_SH=$here/opencode.sh; fi; }
export OPENCODE_SH   # review.sh reads it too
```

  - Replace the ZDR block (`if ! grep -qE '^backend: …' … fi`, 4 lines) with its two body lines, unconditional:

```bash
  zdr=$(cat docs/dev/reviews/.zdr-confirmed 2>/dev/null || echo 1970-01-01)
  [ $(( ( $(date +%s) - $(date -d "$zdr" +%s 2>/dev/null || echo 0) ) / 86400 )) -le 35 ] || { echo; echo "> WARNING: opencode go zero-data-retention for DeepSeek last confirmed $zdr. Check https://opencode.ai/docs/go/ and write today's date to docs/dev/reviews/.zdr-confirmed."; }
```

  In `deploy/nightly/README.md`: delete the four lines from `Claude-only repos (\`backend: claude\`)…` through `…with the dedicated ChatGPT account.`; change `Monthly (opencode repos only):` to `Monthly:`.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/nightly.test.sh`
Expected: all `ok`.

- [ ] **Step 5: Commit**

```bash
git add plugins/core/scripts/nightly.sh tests/nightly.test.sh deploy/nightly/README.md
git commit -m "feat(nightly): prefer the repo's scripts/opencode.sh; ZDR check for every repo"
```

---

### Task 4: opencode agents — orchestrator, rescuer, subagent modes, guards

**Files:**
- Create: `template/.opencode/agents/orchestrator.md`, `template/.opencode/agents/rescuer.md`, `template/opencode.json`
- Modify: `template/.opencode/agents/{worker,reviewer,docs}.md` (line 3 `mode: primary` → `mode: all`)
- Sync: `.opencode/agents/*.md` at the repo root (copy all five from the template)
- Create: `tests/opencode-agents.test.sh`

**Interfaces:**
- Produces: agent names `orchestrator`, `worker`, `rescuer`, `reviewer`, `docs`; `template/opencode.json` with `default_agent: orchestrator`; worktree folder `.opencode/worktrees/<task>` (gitignored in Task 5).

- [ ] **Step 1: Write the failing test** `tests/opencode-agents.test.sh`:

```bash
#!/usr/bin/env bash
# tests/opencode-agents.test.sh — opencode agent modes and models, and the orchestrator's bash guard (mirror of the Claude hooks)
source "$(dirname "$0")/lib.sh"
A=template/.opencode/agents
fm() { sed -n '2,/^---$/p' "$A/$1.md" 2>/dev/null; }
for a in orchestrator worker rescuer reviewer docs; do
  [ -f "$A/$a.md" ] && echo "  ok  $a.md exists" || { echo "  FAIL $a.md missing"; FAILS=$((FAILS+1)); }
  cmp -s "$A/$a.md" ".opencode/agents/$a.md" && echo "  ok  root copy of $a.md in sync" || { echo "  FAIL root .opencode/agents/$a.md differs"; FAILS=$((FAILS+1)); }
done
assert_contains "$(fm orchestrator)" '^mode: primary$' "orchestrator is primary"
assert_contains "$(fm orchestrator)" '^model: openai/gpt-6-sol$' "orchestrator on gpt-6-sol"
assert_contains "$(fm orchestrator)" '^reasoningEffort: medium$' "orchestrator effort medium"
assert_contains "$(fm rescuer)" '^model: openai/gpt-6-sol$' "rescuer on gpt-6-sol"
assert_contains "$(fm rescuer)" '^reasoningEffort: high$' "rescuer effort high"
assert_contains "$(fm rescuer)" '^  bash: deny$' "rescuer has no shell"
for a in worker rescuer reviewer docs; do assert_contains "$(fm $a)" '^mode: all$' "$a usable as subagent and by opencode run"; done
for a in worker reviewer docs; do assert_contains "$(fm $a)" '^model: opencode-go/deepseek-v4.1-flash$' "$a on DeepSeek"; done
assert_eq orchestrator "$(jq -r .default_agent template/opencode.json)" "plain opencode start lands on the orchestrator"

command -v opencode >/dev/null || { echo "  skip live checks (no opencode)"; finish; }
W=$(mktemp -d); mkdir -p "$W/.opencode/agents" "$W/bin"; cp "$A"/*.md "$W/.opencode/agents/"; cp template/opencode.json "$W/"
git -C "$W" init -q; printf 'SECRET=fake\n' > "$W/.env"; printf 'SECRET=\n' > "$W/.env.example"
# `opencode debug agent --tool bash` really executes an allowed command, so every external tool a case names is a stub:
# a broken guard runs a stub, never git/cat/npx for real, and an allowed case must print the stub's marker.
for t in git cat less head grep npx supabase prisma env python node; do printf '#!/usr/bin/env bash\necho "STUB-%s $*"\n' "$t" > "$W/bin/$t"; chmod +x "$W/bin/$t"; done
export PATH="$W/bin:$PATH"
assert_eq orchestrator "$(cd "$W" && timeout 60 opencode debug config 2>/dev/null | jq -r .default_agent)" "resolved default_agent"
assert_eq medium "$(cd "$W" && timeout 60 opencode debug agent orchestrator 2>/dev/null | jq -r .options.reasoningEffort)" "reasoningEffort in the agent's provider options"
call() { (cd "$W" && timeout 60 opencode debug agent orchestrator --tool bash --params "$(jq -nc --arg c "$1" '{command:$c,description:"t"}')" 2>&1); }
denied() { out=$(call "$1"); assert_contains "$out" 'prevents you from using this specific tool call' "orchestrator denies: $1"
  printf '%s' "$out" | grep -q 'STUB-' && { echo "  FAIL denied command still ran: $1"; FAILS=$((FAILS+1)); } || true; }
allowed() { out=$(call "$1"); assert_contains "$out" "$2" "orchestrator runs: $1"; }   # a positive marker, so a timeout or parse error is a FAIL
t20() { printf "$1%.0s" $(seq 1 "$2"); }   # token shapes are built at runtime so none lives in the repo
for c in 'cat .env' 'cd app && cat .env.local' 'source .env.production' 'cat deploy/.env.secrets' 'export $(cat .env | xargs)' \
  'cat "deploy/.env.secrets"' "cat '.env.local'" 'cat .env.local .env.example' 'cat .env.example' 'grep KEY .env .env.example' \
  'git commit -m x --no-verify' 'git push --no-verify' 'cd app && git push origin main --no-verify' \
  'git -c core.hooksPath=/dev/null push' 'git config core.hooksPath /dev/null' 'LEFTHOOK=0 git push' 'LEFTHOOK_EXCLUDE=review git push' \
  'SKIP_REVIEW=1 git push' 'export SKIP_REVIEW=1' 'env SKIP_REVIEW=1 git push' 'command git push --no-verify' 'if true; then git push --no-verify; fi' \
  'npx prisma db push' 'npx prisma migrate reset' 'supabase db reset --linked' \
  "echo ghp_$(t20 a 36)" "echo github_pat_$(t20 a 30)" "echo sk-proj-$(t20 a 20)" "echo sk-ant-$(t20 a 20)" "echo sk_live_$(t20 a 20)" "echo rk_live_$(t20 a 20)" \
  "echo xoxb-$(t20 1 10)" "echo xoxa-$(t20 1 10)" "echo xoxp-$(t20 1 10)" "echo xoxr-$(t20 1 10)" "echo xoxs-$(t20 1 10)" \
  "echo AKIA$(t20 A 16)" "echo ASIA$(t20 A 16)" "echo AIza$(t20 a 35)" "echo glpat-$(t20 a 20)" "echo sb_secret_$(t20 a 8)" \
  "echo eyJ$(t20 a 8).eyJ$(t20 a 8).x" 'echo https://hooks.slack.com/services/T0/B0/x' "echo '-----BEGIN RSA PRIVATE KEY-----'"; do denied "$c"; done
allowed 'git status' 'STUB-git status'
allowed 'git push origin main' 'STUB-git push origin main'
allowed 'npx prisma migrate dev --name add_x' 'STUB-npx prisma migrate dev'
allowed 'supabase db reset' 'STUB-supabase db reset'
allowed 'git worktree add .opencode/worktrees/task-login -b task-login' 'STUB-git worktree add'
rm -rf "$W"; finish
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/opencode-agents.test.sh`
Expected: `FAIL orchestrator.md missing`, `FAIL rescuer.md missing`, mode failures, `jq` error on missing `opencode.json`.

- [ ] **Step 3: Implement.** `template/.opencode/agents/orchestrator.md`:

```markdown
---
description: Orchestrator for this repository. Plans, delegates to the worker/rescuer/reviewer/docs subagents, verifies, runs tests and git, commits.
mode: primary
model: openai/gpt-6-sol
reasoningEffort: medium
permission:
  # Mirror of the Claude hooks (block-unsafe-bash.sh, block-secrets.sh), which do not run in opencode.
  # Each command is split into its parts and every part is checked; the last matching rule wins.
  bash:
    "*": allow
    "*git *--no-verify*": deny
    "*git *--no-gpg-sign*": deny
    "*git *core.hooksPath*": deny
    "*lefthook*--no-verify*": deny
    "*SKIP_REVIEW=*": deny
    "*LEFTHOOK=0*": deny
    "*LEFTHOOK_EXCLUDE=*": deny
    "*prisma db push*": deny
    "*prisma migrate reset*": deny
    "*supabase db reset*--linked*": deny
    "*cat *.env*": deny
    "*less *.env*": deny
    "*more *.env*": deny
    "*head *.env*": deny
    "*tail *.env*": deny
    "*bat *.env*": deny
    "*source *.env*": deny
    ". *.env*": deny
    "*grep *.env*": deny
    "*rg *.env*": deny
    "*sed *.env*": deny
    "*awk *.env*": deny
    "*cut *.env*": deny
    "*cp *.env*": deny
    "*mv *.env*": deny
    "*python* *.env*": deny
    "*node *.env*": deny
    "*eyJ*.eyJ*": deny
    "*sb_secret_*": deny
    "*AKIA*": deny
    "*ASIA*": deny
    "*ghp_*": deny
    "*gho_*": deny
    "*ghu_*": deny
    "*ghs_*": deny
    "*ghr_*": deny
    "*github_pat_*": deny
    # plain "sk-<20+ chars>" has no wildcard form that spares "task-..." branch names; the named prefixes are covered
    "*sk-proj-*": deny
    "*sk-ant-*": deny
    "*sk_live_*": deny
    "*rk_live_*": deny
    "*xoxa-*": deny
    "*xoxb-*": deny
    "*xoxp-*": deny
    "*xoxr-*": deny
    "*xoxs-*": deny
    "*AIza*": deny
    "*glpat-*": deny
    "*hooks.slack.com/services/*": deny
    "*PRIVATE KEY-----*": deny
    # no .env.example carve-outs: wildcards match the whole command, so "cat .env.local .env.example" would slip through.
    # Read .env.example with the read tool instead.
---

You are the orchestrator for this repository. `AGENTS.md` is your rulebook; its `## opencode` section tells you how to brief, run in parallel and verify subagents.

- You plan, decide, delegate, verify and commit. Subagents never commit.
- Scoped edits and code searches → `worker`. Stuck after two attempts → `rescuer`. Spec and plan review → `reviewer`. Docs → `docs`.
- Parallelise as much as possible (see `AGENTS.md`).
- You run the tests and git yourself. Never read `.env` files; read `.env.example` with the read tool, not the shell. Never bypass the git hooks; your bash permission blocks it. When the push review blocks, fix the `[high]` findings or tell the user the exact command they can type themselves.
```

`template/.opencode/agents/rescuer.md`:

```markdown
---
description: Rescue worker for a task another model got stuck on. Same file-only limits as the worker, stronger model. No shell, no subagents, no web.
mode: all
model: openai/gpt-6-sol
reasoningEffort: high
permission:
  bash: deny
  task: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
---

Another model got stuck on this task. Read the problem statement, the failing command and its output first; find the root cause before you edit anything. Then do exactly the task, and stop.

- You have no shell. You cannot run the app, the tests, builds or git, so you never need `.env` or any secret file: do not ask for them, do not look for them. The caller runs the tests after you. Non-secret configuration you need is in the task text.
- Use the LSP tool (definitions, references, diagnostics) before grep or whole-file reads.
- Stay inside the task's Files; if something outside looks wrong, mention it instead of fixing it.
- Never open or search `.env`, `.env.*`; `.env.example` is fine for variable names.
- If you cannot finish, stop and report exactly what is done and what is left.

End with this report, exactly these headings:

Summary: what you did, in one or two lines
Files:
- path/to/file — why (one line per file you changed; nothing else)
Verify: commands the caller should run
Partial: false | true (what is left)
SensitiveSeen: none | what secret or personal data you came across (never its value)
```

`template/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "orchestrator"
}
```

In `template/.opencode/agents/worker.md`, `reviewer.md`, `docs.md`: line 3 `mode: primary` → `mode: all`. Then sync the root copies: `cp template/.opencode/agents/*.md .opencode/agents/`

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/opencode-agents.test.sh`
Expected: all `ok`. If an `orchestrator runs:` line fails because the `STUB-` marker is missing, the stubs are not on the PATH opencode's bash sees: stop and report, never rerun with real tools. If a `denies:` line fails, fix the pattern in `orchestrator.md` (opencode wildcards: `*` any run of characters, `?` one character), copy to the root again, rerun. Do not weaken a test case to make it pass.

- [ ] **Step 5: Commit**

```bash
git add template/.opencode template/opencode.json .opencode/agents tests/opencode-agents.test.sh
git commit -m "feat(opencode): orchestrator and rescuer agents, subagent modes, hook guards as bash permissions"
```

---

### Task 5: One template for everyone

**Files:**
- Modify: `copier.yml`, `template/AGENTS.md`, `template/CLAUDE.md`, `template/.claude/settings.json`, `template/mise.toml`
- Delete: `template/.claude/agents/` (worker, rescuer, reviewer, docs), `tests/backend.test.sh`
- Create: `tests/template.test.sh`
- Modify: `tests/e2e.test.sh`

**Interfaces:**
- Consumes: `template/opencode.json`, five agents (Task 4); `template/scripts/opencode.sh` (Task 1).
- Produces: rendered repos with no `backend` answer, no `.claude/agents/`, `AGENTS.md` sections `## Models`, `## Parallel work`, `## opencode`, `## Gates (do not bypass)`.

- [ ] **Step 1: Write the failing test** `tests/template.test.sh`:

```bash
#!/usr/bin/env bash
# tests/template.test.sh — one rendered layout for everyone (0.5.0: no backends)
source "$(dirname "$0")/lib.sh"
C=(copier); command -v copier >/dev/null || { command -v uvx >/dev/null && C=(uvx copier) || { echo "  skip template render (no copier/uvx)"; exit 0; }; }
R=$PWD; P=$(mktemp -d); T=$P/fx
"${C[@]}" copy --trust --skip-tasks --defaults --data project_name=fx --data tenant=single --quiet "$R" "$T" >/dev/null 2>"$P/err" || { echo "  FAIL copier copy: $(tail -1 "$P/err")"; FAILS=$((FAILS+1)); rm -rf "$P"; finish; }
assert_exit 0 jq -e . "$T/.claude/settings.json"
! grep -rq '{%\|{{' "$T/.claude" "$T/AGENTS.md" "$T/CLAUDE.md" "$T/mise.toml" "$T/opencode.json" && echo "  ok  no jinja left" || { echo "  FAIL jinja left"; FAILS=$((FAILS+1)); }
assert_eq true "$(jq '.enabledPlugins["codex@openai-codex"]' "$T/.claude/settings.json")" "codex plugin on (spec review)"
assert_eq opus "$(jq -r .model "$T/.claude/settings.json")" "Claude orchestrator opus"
[ ! -e "$T/.claude/agents" ] && echo "  ok  no Claude project agents" || { echo "  FAIL .claude/agents rendered"; FAILS=$((FAILS+1)); }
assert_eq 5 "$(ls "$T/.opencode/agents" | wc -l | tr -d ' ')" "five opencode agents"
assert_eq orchestrator "$(jq -r .default_agent "$T/opencode.json")" "opencode default agent"
[ -f "$T/scripts/opencode.sh" ] && [ -f "$T/scripts/review.sh" ] && echo "  ok  runner ships next to review.sh" || { echo "  FAIL scripts missing"; FAILS=$((FAILS+1)); }
assert_contains "$(cat "$T/mise.toml")" '^OPENCODE_EXPERIMENTAL_LSP_TOOL = "true"' "LSP tool for interactive opencode"
assert_eq "" "$(grep -n 'core:worker\|core:rescue\|core:review\|core:handoff\|worker\.sh\|backend' "$T/AGENTS.md" "$T/CLAUDE.md" "$T/.copier-answers.yml")" "no obsolete references"
assert_contains "$(cat "$T/AGENTS.md")" '^## opencode' "opencode contract section"
assert_contains "$(cat "$T/AGENTS.md")" '^## Parallel work' "parallelise rule"
assert_contains "$(cat "$T/CLAUDE.md")" 'codex:codex-rescue' "spec/plan review by Codex"
[ "$(wc -l < "$T/AGENTS.md")" -le 150 ] && echo "  ok  AGENTS.md <= 150 lines" || { echo "  FAIL AGENTS.md too long"; FAILS=$((FAILS+1)); }
rm -rf "$P"; finish
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/template.test.sh`
Expected: failures on `no Claude project agents`, `LSP tool`, `no obsolete references`, `## opencode`, `## Parallel work`, `codex:codex-rescue` (or the skip line if copier/uvx is missing — then install copier with `mise use -g pipx:copier` and rerun; this test must actually run once).

- [ ] **Step 3: Implement.**

`copier.yml`: delete the `_exclude:` key and its two lines; delete the whole `backend:` question (5 lines); add `  - opencode.json` under `_skip_if_exists` after `  - .claude/rules/**`. Copier runs string tasks in the system shell (cmd on native Windows), where single quotes and `/dev/null` break, so replace the existing `.claude/worktrees/` task with an argument-list task that always runs bash and covers both folders:

```yaml
  # parallel workers create .claude/worktrees/ (Claude) and .opencode/worktrees/ (opencode); append, never overwrite the repo's own .gitignore.
  # Argument list, not a string: copier would run a string in cmd on native Windows.
  - command: [bash, -c, "for d in .claude/worktrees/ .opencode/worktrees/; do grep -qxF \"$d\" .gitignore 2>/dev/null || echo \"$d\" >> .gitignore; done"]
```

Leave the `mise install && lefthook install` task as it is (no quotes or redirects that differ between shells).

`template/.claude/settings.json` (whole file, no Jinja):

```json
{
  "enabledPlugins": {
    "core@campanha-dev-standards": true,
    "superpowers@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "codex@openai-codex": true,
    "impeccable@impeccable": true
  },
  "extraKnownMarketplaces": {
    "campanha-dev-standards": { "source": { "source": "github", "repo": "stickman874/campanha-dev-standards" } },
    "openai-codex": { "source": { "source": "github", "repo": "openai/codex-plugin-cc" } },
    "impeccable": { "source": { "source": "github", "repo": "pbakaus/impeccable" } }
  },
  "model": "opus",
  "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "haiku" },
  "sandbox": { "enabled": true, "autoAllowBashIfSandboxed": true },
  "permissions": { "deny": ["Read(./.env)", "Read(./.env.*)"], "allow": ["Read(./.env.example)"] }
}
```

`template/mise.toml`: replace line 2 (the Jinja comment) with:

```toml
# opencode is not installable by mise: curl -fsSL https://opencode.ai/install | bash, then opencode auth login (opencode go, and OpenAI for the orchestrator).
```

and append:

```toml

[env]
OPENCODE_EXPERIMENTAL_LSP_TOOL = "true"   # LSP tool in interactive opencode sessions; needs `mise activate` in your shell
```

`template/AGENTS.md`: in `## Communication` change the last bullet to `- Multiple choice: use the tool's option selector, and mark one option \`(recommended)\`.` Replace the whole `## Models` section (heading through the `{% if backend == 'opencode' %}- Without Claude…{% endif %}` line) with:

```markdown
## Models
- Orchestrator (plans, decides, reviews, commits): Claude Code → Opus; opencode → the `orchestrator` agent (gpt-6-sol). Never Kimi.
- Claude Code: the superpowers skills own the process; see `CLAUDE.md`.
- opencode: subagents in `.opencode/agents/`; see `## opencode` below.
- On a quota or rate-limit error, fall back to the next option and say so in one line. No retry loops.

## Parallel work
- Parallelise as much as possible: split work into independent, non-overlapping tasks (different files or modules) and dispatch them all at once.
- Serialise only when one task consumes another's output or two tasks touch the same file. Sequential dispatch is the exception, not the default.
- Commit before dispatching: parallel workers start from the last commit in their own worktree and never see uncommitted changes.

## opencode
- Subagents: `worker` (DeepSeek; scoped edits and code searches, no shell), `rescuer` (gpt-6-sol; when stuck), `reviewer` (DeepSeek; read-only), `docs` (DeepSeek; `docs/` and `CHANGELOG.md` only).
- Brief: `Outcome` (what must exist), `Files` (read first; the only files it may change), `Keep` (must not change), `Config` (non-secret values; it has no shell and no `.env`). One outcome per call.
- Before a worker: commit or stash your own changes, so every change in `git status` afterwards is the worker's.
- In parallel: the task tool cannot target another folder, so per task run `git worktree add .opencode/worktrees/<task> -b <task>`, then `opencode run --agent worker --dir .opencode/worktrees/<task> --auto "<brief>"`, all started together. Workers never commit: check each, commit inside its worktree, cherry-pick onto your branch, `git worktree remove`.
- After it returns: the files it claims vs `git status --short` (claimed but unchanged = false claim); read `git diff`; run the related test yourself, trimmed (`| tail -40`). One correction round with the exact error pasted; still failing → `rescuer` or you. On an error or limit, keep or revert its partial changes before handing over. `SensitiveSeen` other than `none`: check nothing secret landed; if it did, rotate it and tell the user.
- Stuck: `rescuer` with the problem, the failing command and its output; verify with `git diff` and that command before trusting "done".
- Specs and plans (substantial work only): `reviewer` with "Adversarially review the spec/plan at <path>: assumptions, alternatives, failure modes, migration gaps; answer in prose." Decide with the user; one line per rejected finding under `## Review notes`.
```

In `## Where things are`: delete the line `- Handoffs arrive as a pasted prompt; …`. In `## Gates (do not bypass)` change the push bullet to:

```markdown
- push: typecheck, tests related to the changed files (`vitest related`); `scripts/review.sh` (DeepSeek on opencode go, read-only) when the diff touches auth, API handlers, db or the gates. Blocked: read the `[high]` lines, fix, commit, push again; max 3 rounds, then show the findings to the user. On demand: `bash scripts/review.sh <base>`.
```

`template/CLAUDE.md` (whole file):

```markdown
@AGENTS.md

# Claude-specific
- Process: the superpowers skills. Small tasks (bug, UI tweak): no ritual — do it, run the test, commit. Brainstorm → spec → plan only when the user asks or the change crosses modules. This overrides superpowers' "invoke a skill on a 1% chance" rule.
- Delegation: built-in `general-purpose` subagents with an explicit `model` — `haiku` for scoped edits and searches, `sonnet` when stuck and for visual checks. Parallel: one `Agent` call per task in the same message, each with `isolation: "worktree"`. You run the tests; you commit.
- Stuck: `systematic-debugging` first; then a fresh `general-purpose` subagent on `sonnet` with the problem, the failing command and its output. Verify with `git diff` and that command before trusting "done". `/codex:rescue` is the user's manual escalation.
- Spec and plan review (replaces superpowers' own spec/plan reviewer subagent): `Agent` with `subagent_type: "codex:codex-rescue"` and the prompt `--wait. Read-only, do not edit. Adversarially review the spec/plan at <path>: assumptions, alternatives, failure modes, migration gaps.` Show its output as-is and check `git status` is unchanged. Empty result or error → a `general-purpose` subagent on `sonnet` with the same prompt; say so in one line. Decide with the user; one line per rejected finding under `## Review notes`.
- Push blocked: never bypass; the human can type `SKIP_REVIEW=1 git push` themselves.
- Docs: the night shift refreshes them; run the `doc-keeper` agent (mode diff) only when the user asks or a feature ships.
- Usage: never Agent Teams. Do not enable the Codex plugin's review gate.
- Visual verification: a `sonnet` subagent drives headless Chrome via the Playwright CLI (viewports 1440×900 and 390×844), reads the screenshots, then deletes them.
- Ponytail level lite: smallest change at the right level — colours, components and business rules are fixed at the source, never in the screen.
```

Then: `git rm -rq template/.claude/agents tests/backend.test.sh`

`tests/e2e.test.sh`: in the `copier rendered template` line add `[ -f scripts/opencode.sh ] &&` after `[ -f scripts/review.sh ] &&`.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/template.test.sh && bash tests/e2e.test.sh`
Expected: all `ok` (e2e may print `skip e2e` if lefthook/gitleaks are missing).

- [ ] **Step 5: Commit**

```bash
git add -A copier.yml template tests
git commit -m "feat(template): one layout, superpowers on Claude, opencode contract and parallel-work rule in AGENTS.md"
```

---

### Task 6: Plugin surface, docs and release 0.5.0

**Files:**
- Delete: `plugins/core/skills/` (worker, rescue, review, handoff)
- Modify: `plugins/core/commands/adopt.md`, `.claude-plugin/marketplace.json`, `plugins/core/.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md`, `tests/assets.test.sh`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the failing test** — replace `tests/assets.test.sh` with:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
for f in plugins/core/hooks/*.sh plugins/core/scripts/*.sh template/scripts/*.sh deploy/nightly/*.sh; do assert_exit 0 bash -n "$f"; done
for f in plugins/core/agents/*.md plugins/core/commands/*.md template/.opencode/agents/*.md; do
  assert_eq "---" "$(head -1 "$f")" "frontmatter: $f"; assert_contains "$(head -6 "$f")" 'description:' "description: $f"
done
for f in .claude-plugin/marketplace.json plugins/core/.claude-plugin/plugin.json plugins/core/hooks/hooks.json template/.claude/settings.json template/opencode.json; do assert_exit 0 jq -e . "$f"; done
assert_eq 2 "$(jq '.hooks.PreToolUse[0].hooks | length' plugins/core/hooks/hooks.json)" "two Bash hooks"
assert_eq ./plugins/core "$(jq -r '.plugins[0].source' .claude-plugin/marketplace.json)" "plugin source"
assert_eq 0.5.0 "$(jq -r .version plugins/core/.claude-plugin/plugin.json)" "version 0.5.0"
[ ! -e plugins/core/skills ] && echo "  ok  plugin ships no skills" || { echo "  FAIL plugins/core/skills still exists"; FAILS=$((FAILS+1)); }
assert_eq "" "$(grep -rln 'core:worker\|core:rescue\|core:review\|core:handoff\|worker\.sh\|claude\.sh\|codex\.sh\|backend' plugins template deploy .claude-plugin)" "no obsolete references in shipped files"
PY=python3; command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1 || PY=python   # Windows ships only `python` (python3 may be a Store-alias stub)
assert_exit 0 "$PY" -c 'import yaml; yaml.safe_load(open("copier.yml"))'
finish
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/assets.test.sh`
Expected: `FAIL version 0.5.0`, `FAIL plugins/core/skills still exists`, `FAIL no obsolete references…`.

- [ ] **Step 3: Implement.**

`git rm -rq plugins/core/skills`

`plugins/core/.claude-plugin/plugin.json`: `"version": "0.5.0"`.

`.claude-plugin/marketplace.json` plugin description:

```
"Two Bash hooks, doc-keeper agent, /adopt and /docs-consolidate commands, push review and night shift over opencode go (DeepSeek); project template via copier (lefthook gates, opencode agents, AGENTS.md process rules for Claude Code with superpowers and for opencode, mise.toml, docs tree)."
```

`plugins/core/commands/adopt.md`:
  - Step 1: replace `(answer project name, tenant and backend; explain tenant or backend in one sentence if asked — … on the Codex login does worker, rescue and review)` with `(answer project name and tenant; explain tenant in one sentence if asked)`. Append: `Already adopted on a version before 0.5.0: follow "Upgrading to 0.5.0" in the campanha-dev-standards README instead.`
  - Step 2: replace the sentence from `` `scripts/review.sh` and the agents come from the template:`` to the end of the step with: `` `scripts/review.sh`, `scripts/opencode.sh`, `opencode.json` and `.opencode/agents/{orchestrator,worker,rescuer,reviewer,docs}.md` come from the template; each dev runs `opencode auth login` once for opencode go (push review) and once for OpenAI (the opencode orchestrator), and `codex login` for the Claude spec review. ``
  - Step 7: `7. Commit on branch \`chore/adopt-standards\`.`

`README.md`:
  - Line 3 tagline: `One development methodology for every project: gates, living docs, cross-vendor review, a night shift. Company-agnostic. A Claude Code plugin + a copier template.`
  - Replace the `## Install (once per person)` block (from the heading through the Codex-repos paragraph, keeping the `/plugin …` lines) with:

```markdown
## Install (once per person)

    curl https://mise.run | sh                           # mise installs the pinned tools per repo
    # then activate it in your shell (once): bash `echo 'eval "$(mise activate bash)"' >> ~/.bashrc`,
    # zsh `echo 'eval "$(mise activate zsh)"' >> ~/.zshrc`, PowerShell `mise activate pwsh | Out-String | Invoke-Expression` in $PROFILE
    curl -fsSL https://opencode.ai/install | bash        # opencode; then opencode auth login twice: OpenCode Go ($10/dev, push review) and OpenAI (orchestrator)
    npm i -g @openai/codex && codex login                # Codex CLI: reviews specs and plans from Claude Code (plugin openai/codex-plugin-cc, enabled by the template)

Use Claude Code, opencode or both; each runs on its own subagents. Claude Code: Opus orchestrates, the superpowers skills run the process, specs and plans are reviewed by Codex. opencode: the `orchestrator` agent (gpt-6-sol) delegates to `worker`/`reviewer`/`docs` (DeepSeek) and `rescuer` (gpt-6-sol). Push review and night shift run on opencode go.
```

  - Adopt block: `# asks project name, tenant (backend …)` comment → `# asks project name and tenant`.
  - In `## What you get` replace the `Usage economy`, `Secrets`, and `core:worker …` bullets with:

```markdown
- Process: Claude Code follows superpowers (brainstorm → spec → plan → execution), with Codex reviewing specs and plans (`codex:codex-rescue`, read-only); opencode follows the `## opencode` contract in `AGENTS.md`. Both orchestrators parallelise as much as possible.
- Secrets: sandbox + `permissions.deny` in the Claude settings template; opencode denies dotenv reads natively and the `orchestrator` agent's bash permission mirrors the Claude hooks.
- One unattended runner, `scripts/opencode.sh` (`opencode run --format json`), shipped next to `scripts/review.sh` and used by the night shift.
```

  - Add before `## Develop the plugin`:

```markdown
## Upgrading to 0.5.0 (any tool)

Tell your agent "apply the 0.5.0 upgrade from the campanha-dev-standards README", or do it by hand:

1. Update the plugin, then in each repo right away: `copier update --trust` (the stale `backend:` answer is ignored; `.opencode/agents/`, `opencode.json` and `scripts/opencode.sh` arrive; unedited `.claude/agents/*` are removed — delete edited ones by hand).
2. `AGENTS.md` and `CLAUDE.md` are never rewritten by copier. In `AGENTS.md`, take from the template's `AGENTS.md`: the last bullet of `## Communication`, the whole `## Models`, `## Where things are` and `## Gates (do not bypass)` sections, and the new `## Parallel work` and `## opencode` sections; keep your own `## Commands`, `## Conventions` and `## Exceptions`. Replace `CLAUDE.md` with the template's, then re-add any project-specific lines you had. An existing `opencode.json`: add `"default_agent": "orchestrator"`. `.claude/settings.json`: set `"model": "opus"`, add the `codex@openai-codex` plugin and the `openai-codex` marketplace.
3. Every dev: opencode go login (the push review needs it), OpenAI login in opencode, and `codex login`.
4. Check — this must print nothing: `grep -rn 'core:worker\|core:rescue\|core:review\|core:handoff\|worker.sh\|backend\|Handoffs arrive\|Sonnet, read-only\|gpt-6-sol, read-only' AGENTS.md CLAUDE.md`
5. Your own files outside the repo, if they mention the old skills: `~/.agents/AGENTS.md` (model routing table), `~/.claude/CLAUDE.md` (worker dispatch line).
```

  - Designs line: append `, [2026-09-24 v4 native subagents](docs/superpowers/specs/2026-09-24-v4-native-subagents-design.md)` before the final period.

`CHANGELOG.md`: under `## [Unreleased]` insert:

```markdown
## [0.5.0] - 2026-09-24

### Changed
- No backends: the copier `backend` question is gone. Claude Code runs on superpowers plus built-in subagents (Opus orchestrator); opencode runs on `.opencode/agents/` with a new `orchestrator` (gpt-6-sol, medium, default agent via `opencode.json`) and a new `rescuer` (gpt-6-sol, high); `worker`, `reviewer` and `docs` are `mode: all`.
- `scripts/opencode.sh` ships in the template next to `review.sh`; `review.sh` no longer searches the Claude plugin cache. The night shift prefers the repo's runner and checks the ZDR date for every repo.
- Specs and plans are reviewed by another vendor: Codex through the `codex:codex-rescue` subagent on Claude Code, the DeepSeek `reviewer` on opencode.
- `AGENTS.md`: `## Parallel work` (parallelise as much as possible) and the `## opencode` worker contract. `mise.toml` sets `OPENCODE_EXPERIMENTAL_LSP_TOOL` for interactive opencode sessions.

### Removed
- Skills `core:worker`, `core:rescue`, `core:review`, `core:handoff`; runners `worker.sh`, `claude.sh`, `codex.sh`; `template/.claude/agents/`.

### Security
- The opencode `orchestrator`'s bash permission denies what the Claude hooks deny (gate bypasses, dotenv reads, destructive database commands, token shapes), tested against opencode's own permission check.
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/assets.test.sh`
Expected: all `ok`.

- [ ] **Step 5: Commit**

```bash
git add -A plugins .claude-plugin README.md CHANGELOG.md tests/assets.test.sh
git commit -m "release: 0.5.0 (native subagents per tool)"
```

---

### Task 7: Whole-branch verification

**Files:** none changed unless a check fails.

- [ ] **Step 1: Full suite** — `bash tests/run.sh` (run in the background; it takes several minutes). Expected: exit 0, no `FAIL` lines. `skip` lines are allowed only for tools genuinely missing; `tests/template.test.sh` and the live part of `tests/opencode-agents.test.sh` must have run at least once on this machine.
- [ ] **Step 2: Obsolete references** — `grep -rn 'core:worker\|core:rescue\|core:review\|core:handoff' plugins template deploy .claude-plugin .opencode copier.yml` prints nothing (tests, `docs/superpowers/`, `CHANGELOG.md` and `README.md` name them on purpose and are not scanned).
- [ ] **Step 3: Render with tasks on (the gitignore task):** `copier copy --trust --defaults --data project_name=fx --data tenant=single . <tmp>/fx` from Git Bash on this Windows machine (the `mise install && lefthook install` task may fail on a bare dir; that is fine). Expected: `<tmp>/fx/.gitignore` contains exactly the lines `.claude/worktrees/` and `.opencode/worktrees/`, no quotes.
- [ ] **Step 4: Live opencode smoke (spends a few cents):** in the rendered dir, `git init`, one commit, then:
  - Runner + DeepSeek: `echo "Reply with the single word OK." | OPENCODE_TIMEOUT=180 bash scripts/opencode.sh "$PWD" reviewer` → exit 0, output contains `OK`.
  - Ordinary start lands on the orchestrator with the right effort: `opencode run --format json --print-logs --log-level DEBUG "Reply with the single word OK." 2> log.txt > ev.json` (no `--agent`) → `ev.json` has a `text` event containing `OK`; `grep -i 'agent=orchestrator' log.txt` and `grep -i 'reasoningEffort.*medium\|reasoning_effort.*medium' log.txt` each print a line. If the log format names these differently, find the lines that show the agent and the provider options and record them in the PR description; if the effort is not visible at all, say so there (spec risk 2) instead of claiming it.
  - Delete `log.txt` and `ev.json`.
- [ ] **Step 5: Whole-branch review** by a fresh reviewer on the most capable model; fix confirmed findings, one commit per fix.

## Review notes

Codex adversarial review via `codex:codex-rescue` (read-only held), 2026-09-24, verdict needs-attention, 7 findings, all accepted:
- [high] `.env.example` allow rules let `cat .env.local .env.example` through → carve-outs removed; the orchestrator reads `.env.example` with the read tool; mixed-file cases added to the test.
- [high] secret families missing (`xoxa/r/s`, `sk-ant-`) → added with a runtime-built case per family. Plain `sk-<20+>` stays uncovered in opencode: no wildcard spares `task-…` names (an allowed case pins that); the Claude hook still covers it on Claude.
- [medium] `debug agent --tool bash` executes commands; `allowed()` passed on any failure → every named tool is a stub, allowed cases need a positive `STUB-` marker, denied cases fail if a stub ran.
- [medium] copier string task breaks under cmd on Windows → argument-list task running bash, checked in Task 7 step 3.
- [medium] upgrade checklist missed `## Where things are` / `## Gates` → listed, grep extended.
- [medium] ordinary start and effective reasoning effort not exercised → Task 7 step 4.
- [medium] obsolete-reference grep matched its own tests → scan limited to shipped paths.
