# campanha-dev-standards v3 (opencode go) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Codex with opencode go (DeepSeek V4.1 Flash) as worker, reviewer and night shift; push blocks only on secrets, typecheck/tests and a sensitive-path review; handoff becomes a prompt; humans can always force a push.

**Architecture:** One shared runner `plugins/core/scripts/opencode.sh` calls `opencode run --format json --agent <agent>` on a project-level agent and returns the final text; `worker.sh`, `review.sh` and `nightly.sh` are thin layers over it. Capability limits live in the three agent files (`worker`, `reviewer`, `docs`) as opencode `permission` rules, never in prompt wording. lefthook `pre-push` runs typecheck, tests and `review.sh`; everything else runs nightly on box-one from a systemd timer.

**Tech Stack:** bash + jq + git, opencode ≥ 1.18 (`run --format json`, `--auto`, project agents with `permission`), lefthook, gitleaks, semgrep, trivy, Socket via `npx socket`, systemd timers, copier.

**Spec:** `docs/superpowers/specs/2026-09-15-v3-opencode-go-design.md`

## Global Constraints

- Work on branch `feat/v3-opencode-go`. Commit after every task. Never push. Never bypass hooks (the repo's own hook denies `--no-verify`; write any text that mentions bypass flags with the Write/Edit tools, not through a Bash heredoc).
- All files, comments and commit messages in English. Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Scripts: bash, depend only on `jq`, `git`, `grep`, `sed`, coreutils. Hooks always exit 0 and deny via JSON `permissionDecision`.
- Model id in one place per agent frontmatter: `opencode-go/deepseek-v4.1-flash`; `OPENCODE_MODEL` env overrides at run time.
- Never write a literal secret-shaped string anywhere. Tests build tokens at runtime with `printf`.
- Tests assert behaviour (exit codes, output, files), never "file contains this sentence". Run all with `bash tests/run.sh`; it must pass at the end of every task. Fake `opencode` binaries emit the real event shape: one JSON object per line, `{"type":"text","part":{"text":"..."}}`, `{"type":"tool_use","part":{"tool":"edit","state":{"status":"completed"}}}`, `{"type":"step_finish","part":{"tokens":{"total":N},"cost":C}}`, `{"type":"error","error":{"message":"..."}}`.
- When a task deletes a file, delete its test and every reference (`grep -rn <name> .` empty except CHANGELOG history and the v2 spec/plan).
- Ponytail: shortest diff that works; no scaffolding for later.

---

## File structure (end state)

```
plugins/core/
  scripts/opencode.sh      # NEW shared runner (Task 1)
  scripts/worker.sh        # rewritten over opencode.sh (Task 2)
  scripts/review.sh        # NEW (Task 3); same file copied to template/scripts/review.sh
  scripts/nightly.sh       # NEW (Task 4)
  skills/worker/SKILL.md   # updated (Task 2)
  skills/review/SKILL.md   # NEW, replaces skills/codex-review (Task 3)
  skills/rescue/SKILL.md   # NEW (Task 5)
  skills/handoff/SKILL.md  # rewritten (Task 5)
  hooks/block-unsafe-bash.sh  # SKIP_REVIEW + anchored bypass rules (Task 5)
  agents/doc-keeper.md, commands/*.md  # wording only (Task 6)
template/
  .opencode/agents/worker.md      # renamed from deepseek-worker.md (Task 2)
  .opencode/agents/reviewer.md    # NEW (Task 3)
  .opencode/agents/docs.md        # NEW (Task 4)
  scripts/review.sh               # NEW (Task 3); scripts/codex-review.sh and scripts/docs-check.sh deleted (Task 3)
  lefthook.yml, mise.toml, CLAUDE.md, AGENTS.md  # (Tasks 3, 6)
  docs/dev/reviews/.gitkeep       # (Task 4)
deploy/nightly/{nightly.service,nightly.timer,run-all.sh,README.md}  # (Task 4)
tests/opencode.test.sh, worker.test.sh, review.test.sh, nightly.test.sh, hooks-bash.test.sh, assets.test.sh, e2e.test.sh
```

---

### Task 1: Shared runner `opencode.sh`

**Files:**
- Create: `plugins/core/scripts/opencode.sh`
- Test: `tests/opencode.test.sh`

**Interfaces:**
- Produces: `bash opencode.sh <repo> <agent> < prompt`. Env: `OPENCODE_MODEL` (adds `-m`), `OPENCODE_TIMEOUT` (seconds, default 600), `OPENCODE_EVENTS` (path where raw JSON events are saved; callers count `tool_use` there). stdout: the agent's final text (all `text` events, newline-joined). stderr last line: `opencode: tools=N tokens=T cost=C`. Exit 0 done; exit 3 with first stdout line `DEEPSEEK_UNAVAILABLE: <why>` (opencode missing, agent file missing, usage/rate limit or auth error on stderr, `error` event, timeout, non-zero exit), partial text follows; exit 2 bad usage or empty prompt.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/opencode.test.sh
source "$(dirname "$0")/lib.sh"
S="$PWD/plugins/core/scripts/opencode.sh"
W=$(mktemp -d); mkdir -p "$W/bin" "$W/repo/.opencode/agents"
printf -- '---\ndescription: t\n---\n' > "$W/repo/.opencode/agents/worker.md"
git -C "$W/repo" init -q
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"; echo "LSP=$OPENCODE_EXPERIMENTAL_LSP_TOOL" >> "$FAKE_ARGS"
ev() { printf '%s\n' "$1"; }
case $FAKE_MODE in
  ok)    ev '{"type":"step_start"}'; ev '{"type":"tool_use","part":{"tool":"read","state":{"status":"completed"}}}'
         ev '{"type":"text","part":{"text":"Summary: done"}}'; ev '{"type":"step_finish","part":{"tokens":{"total":120},"cost":0.001}}';;
  limit) ev '{"type":"text","part":{"text":"partial"}}'; echo 'level=ERROR error.error="AI_APICallError: 5-hour usage limit reached."' >&2; sleep 30;;
  errev) ev '{"type":"error","error":{"message":"FreeUsageLimitError: free usage exceeded"}}';;
  hang)  sleep 30;;
  fail)  echo boom >&2; exit 1;;
esac
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
run() { FAKE_MODE=$1 bash "$S" "${@:2}"; }

out=$(echo "do x" | OPENCODE_EVENTS="$W/ev" run ok "$W/repo" worker 2> "$W/err"); code=$?
assert_eq 0 "$code" "ok exits 0"
assert_eq "Summary: done" "$out" "stdout is the final text only"
assert_contains "$(cat "$W/err")" 'opencode: tools=1 tokens=120 cost=0.001' "summary on stderr"
assert_eq 1 "$(jq -c 'select(.type=="tool_use")' "$W/ev" | wc -l)" "events saved to OPENCODE_EVENTS"
a=$(cat "$FAKE_ARGS")
assert_contains "$a" '^--format$' "json format"; assert_contains "$a" '^json$' "json format value"
assert_contains "$a" '^worker$' "agent passed"; assert_contains "$a" '^--auto$' "unattended"; assert_contains "$a" 'LSP=true' "LSP enabled"
echo x | OPENCODE_MODEL=p/m run ok "$W/repo" worker >/dev/null 2>&1; assert_contains "$(cat "$FAKE_ARGS")" '^p/m$' "OPENCODE_MODEL adds -m"
echo x | run ok "$W/repo" worker >/dev/null 2>&1; assert_eq 0 "$(grep -c '^-m$' "$FAKE_ARGS")" "no -m without OPENCODE_MODEL"
rm -f "$W/canary"; echo "Fix \`touch $W/canary\` and \$(touch $W/canary)" | run ok "$W/repo" worker >/dev/null 2>&1
[ -e "$W/canary" ] && { echo "  FAIL prompt text executed"; FAILS=$((FAILS+1)); } || echo "  ok  prompt text never executed"
start=$(date +%s); out=$(echo x | run limit "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "usage limit: exit 3"; assert_contains "$out" '^DEEPSEEK_UNAVAILABLE: .*usage limit' "reason first"; assert_contains "$out" 'partial' "partial text returned"
[ $(( $(date +%s) - start )) -lt 10 ] && echo "  ok  gives up early" || { echo "  FAIL waited"; FAILS=$((FAILS+1)); }
out=$(echo x | run errev "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "error event: exit 3"; assert_contains "$out" 'FreeUsageLimitError' "error event message reported"
out=$(echo x | OPENCODE_TIMEOUT=2 run hang "$W/repo" worker 2>/dev/null); code=$?
assert_eq 3 "$code" "hang: exit 3"; assert_contains "$out" 'timeout after 2s' "timeout reported"
out=$(echo x | run fail "$W/repo" worker 2>/dev/null); assert_contains "$out" 'DEEPSEEK_UNAVAILABLE: opencode exited 1' "crash reported"
out=$(echo x | run ok "$W/repo" nosuch 2>/dev/null); code=$?; assert_eq 3 "$code" "missing agent file: exit 3"; assert_contains "$out" 'nosuch.md missing' "names the agent file"
out=$(echo x | PATH=/usr/bin:/bin run ok "$W/repo" worker 2>/dev/null); code=$?; assert_eq 3 "$code" "missing opencode: exit 3"
assert_exit 2 bash "$S" /nonexistent worker
printf '' | run ok "$W/repo" worker >/dev/null 2>&1; assert_eq 2 "$?" "empty prompt: exit 2"
rm -rf "$W"; finish
```

- [ ] **Step 2: Run it, expect FAIL** — `bash tests/opencode.test.sh` → "No such file".

- [ ] **Step 3: Implement**

```bash
#!/usr/bin/env bash
# plugins/core/scripts/opencode.sh
# Runs one project opencode agent unattended and returns its final text. Shared by worker.sh, review.sh and nightly.sh.
#   opencode.sh <repo> <agent> < prompt
# Env: OPENCODE_MODEL (adds -m provider/model), OPENCODE_TIMEOUT (seconds, 600), OPENCODE_EVENTS (save the raw JSON events here).
# stdout: the agent's final text. stderr: diagnostics, then "opencode: tools=N tokens=T cost=C".
# Exit 0 done · 3 "DEEPSEEK_UNAVAILABLE: <why>" (opencode/agent missing, usage or auth error, error event, timeout, crash) · 2 bad usage.
set -u
repo=${1:-}; agent=${2:-}
[ -n "$agent" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: opencode.sh <repo> <agent> < prompt" >&2; exit 2; }
tmp=$(mktemp -d); pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
cat > "$tmp/prompt"; [ -s "$tmp/prompt" ] || { echo "empty prompt" >&2; exit 2; }
events=${OPENCODE_EVENTS:-$tmp/events}; : > "$events"
text() { jq -r 'select(.type=="text") | .part.text' "$events" 2>/dev/null; }
unavailable() {
  [ -n "$pid" ] && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=; }
  echo "DEEPSEEK_UNAVAILABLE: $1"; text; exit 3
}
command -v opencode >/dev/null || unavailable "opencode not installed (curl -fsSL https://opencode.ai/install | bash; opencode auth login)"
[ -f "$repo/.opencode/agents/$agent.md" ] || unavailable ".opencode/agents/$agent.md missing in the project (run copier update)"
LIMIT='usage limit|rate limit|quota|insufficient (balance|credit)|FreeUsageLimit|\b40[13]\b|unauthorized|not logged in'   # opencode retries these silently and never exits
model=(); [ -n "${OPENCODE_MODEL:-}" ] && model=(-m "$OPENCODE_MODEL")
export OPENCODE_EXPERIMENTAL_LSP_TOOL=true
timeout=${OPENCODE_TIMEOUT:-600}; end=$(( $(date +%s) + timeout ))
(cd "$repo" && exec opencode run --format json --agent "$agent" --dir "$repo" --auto ${model[@]+"${model[@]}"} --print-logs --log-level ERROR "$(cat "$tmp/prompt")") > "$events" 2> "$tmp/err" &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(grep -m1 -iE "$LIMIT" "$tmp/err" | sed 's/.*error\.error="//; s/"$//' | cut -c1-200)"
  [ "$(date +%s)" -ge "$end" ] && unavailable "timeout after ${timeout}s"
  sleep 1
done
wait "$pid"; code=$?; pid=
grep -qiE "$LIMIT" "$tmp/err" && unavailable "$(grep -m1 -iE "$LIMIT" "$tmp/err" | cut -c1-200)"
err=$(jq -r 'select(.type=="error") | (.error.message // .error // .) | tostring' "$events" 2>/dev/null | head -1)
[ -n "$err" ] && unavailable "opencode error: ${err:0:200}"
[ "$code" -eq 0 ] || unavailable "opencode exited $code: $(grep -v '^[[:space:]]*$' "$tmp/err" | tail -1 | cut -c1-200)"
text
echo "opencode: tools=$(jq -c 'select(.type=="tool_use")' "$events" 2>/dev/null | wc -l) tokens=$(jq -s '[.[] | select(.type=="step_finish") | .part.tokens.total] | add // 0' "$events") cost=$(jq -s '[.[] | select(.type=="step_finish") | .part.cost] | add // 0' "$events")" >&2
```

- [ ] **Step 4: Run tests, expect PASS** — `bash tests/opencode.test.sh`; then `bash tests/run.sh` still green.

- [ ] **Step 5: Commit** — `git add plugins/core/scripts/opencode.sh tests/opencode.test.sh && git commit -m "feat(core): opencode.sh shared runner over opencode run --format json"`

---

### Task 2: `worker.sh` over the runner; `worker` agent; skill update

**Files:**
- Modify: `plugins/core/scripts/worker.sh` (whole file)
- Rename: `template/.opencode/agents/deepseek-worker.md` → `template/.opencode/agents/worker.md` (content updated)
- Modify: `plugins/core/skills/worker/SKILL.md`, `tests/worker.test.sh` (whole files)

**Interfaces:**
- Consumes: `opencode.sh` (Task 1).
- Produces: `bash worker.sh <repo> < task`. stdout: worker report, `--- git status`, optional `--- claimed but unchanged` (paths named under `Files:` that git does not see as changed). Exit 0 done; 3 `DEEPSEEK_UNAVAILABLE` (from the runner, passed through); 4 wrote nothing (≥3 tool calls, no file changed); 2 bad usage / dirty tree. Env `WORKER_TIMEOUT` (600).

- [ ] **Step 1: Replace `tests/worker.test.sh`**

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
D="$PWD/plugins/core/scripts/worker.sh"
W=$(mktemp -d); mkdir -p "$W/bin" "$W/repo/.opencode/agents"
cp template/.opencode/agents/worker.md "$W/repo/.opencode/agents/"
git -C "$W/repo" init -q; echo a > "$W/repo/a.ts"; git -C "$W/repo" add .; git -C "$W/repo" -c user.name=t -c user.email=t@t commit -qm init
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
ev() { printf '%s\n' "$1"; }
tool() { ev '{"type":"tool_use","part":{"tool":"edit","state":{"status":"completed"}}}'; }
case $FAKE_MODE in
  ok)       tool; echo x > touched.txt; ev '{"type":"text","part":{"text":"Summary: done\nFiles:\n- touched.txt — created\n- ghost.ts — edited\nVerify: npm test\nPartial: false\nSensitiveSeen: none"}}';;
  nothing)  tool; tool; tool; ev '{"type":"text","part":{"text":"Summary: done\nFiles:\n- a.ts — edited"}}';;
  limit)    echo x > half.txt; echo 'level=ERROR error.error="AI_APICallError: usage limit"' >&2; sleep 30;;
esac
ev '{"type":"step_finish","part":{"tokens":{"total":5},"cost":0}}'
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
ws() { git -C "$W/repo" checkout -q -- .; git -C "$W/repo" clean -fdq; FAKE_MODE=$1 bash "$D" "${@:2}"; }

out=$(echo "Outcome: x" | ws ok "$W/repo" 2>/dev/null); code=$?
assert_eq 0 "$code" "success exits 0"
assert_contains "$out" 'Summary: done' "worker report returned"
assert_contains "$out" '?? touched.txt' "git status shows changes"
assert_contains "$(cat "$FAKE_ARGS")" '^worker$' "uses the worker agent"
assert_contains "$out" 'claimed but unchanged' "cross-check section present"
assert_contains "$out" '^ghost.ts$' "claimed file git did not see is listed"
printf '%s' "$out" | sed -n '/claimed but unchanged/,$p' | grep -q 'touched.txt' && { echo "  FAIL real change listed as missing"; FAILS=$((FAILS+1)); } || echo "  ok  real change not listed as missing"
out=$(echo x | ws nothing "$W/repo" 2>&1); code=$?
assert_eq 4 "$code" "wrote nothing: exit 4"; assert_contains "$out" 'wrote nothing (3 tool calls' "wrote nothing reported"
out=$(echo x | ws limit "$W/repo" 2>/dev/null); code=$?
assert_eq 3 "$code" "usage limit: exit 3"; assert_contains "$out" 'DEEPSEEK_UNAVAILABLE' "unavailable passed through"; assert_contains "$out" 'half.txt' "partial edits listed"
echo dirty >> "$W/repo/a.ts"; rm -f "$FAKE_ARGS"; out=$(echo x | FAKE_MODE=ok bash "$D" "$W/repo" 2>&1); code=$?
assert_eq 2 "$code" "dirty tree refused"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL launched on dirty tree"; FAILS=$((FAILS+1)); } || echo "  ok  not launched on dirty tree"
assert_exit 2 bash "$D" /nonexistent
rm -rf "$W"; finish
```

- [ ] **Step 2: Run, expect FAIL** — `bash tests/worker.test.sh` (agent file missing, old script).

- [ ] **Step 3: Implement `plugins/core/scripts/worker.sh`**

```bash
#!/usr/bin/env bash
# DeepSeek worker through the project's no-shell `worker` opencode agent (.opencode/agents/worker.md).
#   worker.sh <repo> < task     the worker edits files and never commits.
# stdout: its report, "--- git status", and "--- claimed but unchanged" (paths under Files: that git does not see).
# Exit 0 done · 3 DEEPSEEK_UNAVAILABLE (caller falls back to a Sonnet subagent) · 4 wrote nothing (≥3 tool calls, no change) · 2 bad usage.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${1:-}; git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: worker.sh <repo> < task" >&2; exit 2; }
[ -z "$(git -C "$repo" status --porcelain)" ] || { echo "working tree has uncommitted changes: commit or stash first, so the worker's edits can be told apart and undone" >&2; exit 2; }
events=$(mktemp); trap 'rm -f "$events"' EXIT
out=$(OPENCODE_EVENTS=$events OPENCODE_TIMEOUT=${WORKER_TIMEOUT:-600} bash "$here/opencode.sh" "$repo" worker); code=$?
echo "$out"
changed=$(git -C "$repo" status --porcelain)
echo "--- git status"; echo "$changed"
[ "$code" -eq 0 ] || exit "$code"
tools=$(jq -c 'select(.type=="tool_use")' "$events" 2>/dev/null | wc -l)
[ -z "$changed" ] && [ "$tools" -ge 3 ] && { echo "worker: wrote nothing ($tools tool calls, no file changed)" >&2; exit 4; }
# ponytail: claims are the "- path — why" lines under Files:; anything git did not see is listed and the caller decides
claimed=$(printf '%s\n' "$out" | sed -n '/^Files:/,/^[A-Z][a-zA-Z]*:/p' | sed -n 's/^- \([^ ]*\).*/\1/p' | sort -u)
missing=$(for f in $claimed; do printf '%s\n' "$changed" | grep -qF -- "$f" || echo "$f"; done)
[ -n "$missing" ] && { echo "--- claimed but unchanged"; echo "$missing"; }
exit 0
```

- [ ] **Step 4: Agent file** — `git mv template/.opencode/agents/deepseek-worker.md template/.opencode/agents/worker.md`, content:

```markdown
---
description: Unattended worker for scoped edits and code searches. No shell, no subagents, no web; it touches files only through the native tools.
mode: primary
model: opencode-go/deepseek-v4.1-flash
permission:
  bash: deny
  task: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
---

You are a worker. Do exactly the task you were given, then stop.

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

- [ ] **Step 5: Skill** `plugins/core/skills/worker/SKILL.md`:

```markdown
---
name: worker
description: Use to hand a well-scoped edit or code search to DeepSeek V4.1 Flash on opencode go (cheap, no shell) instead of a Sonnet subagent. Runs a script, not a subagent; on DEEPSEEK_UNAVAILABLE redo the task with a Sonnet subagent.
---

# DeepSeek worker

    bash "<base directory>/../../scripts/worker.sh" "<absolute repo path>" <<'TASK_END'
    Outcome: the behaviour or artifact that must exist
    Files: exact files to read first, and the only files it may change
    Keep: behaviour and files that must stay as they are
    Config: any non-secret values it needs (it has no shell and no .env)
    TASK_END

Bash timeout 660000 ms. Commit or stash your own changes first (it refuses a dirty tree). The quoted heredoc keeps backticks and `$(...)` from running in your shell. One outcome per call.

After it returns:
- Exit 3 `DEEPSEEK_UNAVAILABLE`: read the partial output and `git status`. Every change is the worker's: keep or revert (`git checkout -- <file>`, `git clean -f <file>`). Give the task to a Sonnet subagent (`Agent` tool, `model: sonnet`) with that state described. Retry DeepSeek once at the next milestone, never in a loop.
- Exit 4 "wrote nothing": the worker read but did not edit. Sharpen `Files:` and `Outcome:` and call once more; then Sonnet.
- Exit 0: check `--- claimed but unchanged` (files it says it edited but git does not see: treat the claim as false), read the diff, run the relevant test file yourself, trimmed: `npm test -- --run <file> 2>&1 | tail -40`. One failure → one more call with the error pasted under the same task, or fix it yourself if small. Still failing → Sonnet or you.
- `SensitiveSeen` other than `none`: check nothing secret landed in files or output; if it did, rotate it and tell the user.
- It never commits; you do.
```

- [ ] **Step 6: `bash tests/run.sh` green; `grep -rn 'deepseek-worker' plugins tests template README.md` → empty (README is fixed in Task 6; if it still matches here, leave README for Task 6). Commit** — `git add -A plugins/core/scripts/worker.sh plugins/core/skills/worker template/.opencode/agents tests/worker.test.sh && git commit -m "refactor(core): worker.sh over opencode.sh; worker agent verified against git status"`

---

### Task 3: `reviewer` agent, `review.sh`, lefthook, `review` skill; Codex and docs-check leave the push

**Files:**
- Create: `template/.opencode/agents/reviewer.md`, `plugins/core/scripts/review.sh`, `template/scripts/review.sh` (identical copy), `plugins/core/skills/review/SKILL.md`, `tests/review.test.sh`
- Delete: `template/scripts/codex-review.sh`, `template/scripts/docs-check.sh`, `plugins/core/skills/codex-review/`, `tests/codex-review.test.sh`, `tests/docs-check.test.sh`
- Modify: `template/lefthook.yml`, `tests/e2e.test.sh:23-24`

**Interfaces:**
- Consumes: `opencode.sh` (Task 1). `review.sh` locates it as `$here/opencode.sh` when present (plugin copy) else `$CLAUDE_PLUGIN_ROOT/scripts/opencode.sh` else `~/.claude/plugins/cache/*/campanha-dev-standards/*/plugins/core/scripts/opencode.sh` (first match). Tests set `OPENCODE_SH=<path>` to override.
- Produces: `bash review.sh` (pre-push stdin, sensitive ranges only), `bash review.sh <from> [<to>]` (explicit, always reviewed, `to` defaults to HEAD), `bash review.sh --all` (stdin ranges, all reviewed). Env: `SKIP_REVIEW=1` logs to `docs/dev/reviews/skipped.log` and exits 0; `REVIEW_TIMEOUT` (300); `OPENCODE_SH`. Prints `[sev] file:line - what - fix` per finding and `review: range=A..B secs=N`. Exit 0 approve/skip; 1 block (verdict block, any high, invalid JSON, reviewer unavailable).

- [ ] **Step 1: Write `tests/review.test.sh`**

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S=$PWD/template/scripts/review.sh; export OPENCODE_SH=$PWD/plugins/core/scripts/opencode.sh
cmp -s "$S" plugins/core/scripts/review.sh && echo "  ok  template and plugin review.sh identical" || { echo "  FAIL review.sh copies differ"; FAILS=$((FAILS+1)); }
W=$(mktemp -d); mkdir -p "$W/bin"
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
case ${FAKE_MODE:-approve} in
  approve)  j='{"verdict":"approve","findings":[]}';;
  block)    j='{"verdict":"block","findings":[{"severity":"high","file":"src/app/api/r.ts","line":3,"what":"no auth check","fix":"call requireUser()"}]}';;
  sneaky)   j='{"verdict":"approve","findings":[{"severity":"high","file":"a.ts","line":1,"what":"x","fix":"y"}]}';;
  prose)    j='Sure! Here is my review. {"verdict":"approve","findings":[{"severity":"low","file":"a.ts","line":1,"what":"nit","fix":"none"}]} Hope this helps.';;
  junk)     j='I could not review this.';;
  limit)    echo 'error.error="AI_APICallError: usage limit"' >&2; sleep 30;;
esac
jq -nc --arg t "$j" '{type:"text",part:{text:$t}}'; echo '{"type":"step_finish","part":{"tokens":{"total":1},"cost":0}}'
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH" FAKE_ARGS="$W/args"
T="$W/repo"; mkdir -p "$T/.opencode/agents"; cp template/.opencode/agents/reviewer.md "$T/.opencode/agents/"; cd "$T"; git init -q -b main
c() { git -c user.name=t -c user.email=t@t commit -qm "$1"; }
mkdir -p src; echo a > src/a.ts; git add -A; c init; git branch base
echo b >> src/a.ts; git add -A; c routine
stdin() { printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" "$(git rev-parse base)"; }

rm -f "$FAKE_ARGS"; out=$(stdin | FAKE_MODE=block bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "stdin routine range: skipped"; assert_contains "$out" 'routine diff' "says why"
[ -e "$FAKE_ARGS" ] && { echo "  FAIL routine range called opencode"; FAILS=$((FAILS+1)); } || echo "  ok  routine range never calls opencode"
out=$(FAKE_MODE=approve bash "$S" base 2>&1); code=$?
assert_eq 0 "$code" "explicit range: reviewed and approved"; assert_contains "$(cat "$FAKE_ARGS")" '^reviewer$' "reviewer agent"
assert_contains "$(cat "$FAKE_ARGS")" 'src/a.ts' "prompt lists changed files"; assert_contains "$(cat "$FAKE_ARGS")" '^+b$' "prompt carries the diff"
out=$(stdin | FAKE_MODE=block bash "$S" --all 2>&1); code=$?
assert_eq 1 "$code" "--all reviews routine ranges and blocks on block"; assert_contains "$out" '\[high\] src/app/api/r.ts:3 - no auth check - call requireUser()' "findings printed as lines"
mkdir -p src/app/api; echo h > src/app/api/r.ts; git add -A; c api
out=$(stdin | FAKE_MODE=approve bash "$S" 2>&1); code=$?; assert_eq 0 "$code" "sensitive range approved passes"; assert_contains "$out" "range=$(git rev-parse base)..$(git rev-parse HEAD)" "logs range"
out=$(stdin | FAKE_MODE=block bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "sensitive range blocked"
out=$(stdin | FAKE_MODE=sneaky bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "approve with a high finding = block"
out=$(stdin | FAKE_MODE=prose bash "$S" 2>&1); code=$?; assert_eq 0 "$code" "JSON inside prose is accepted"; assert_contains "$out" '\[low\] a.ts:1' "finding from prose-wrapped JSON printed"
out=$(stdin | FAKE_MODE=junk bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "no JSON = block"; assert_contains "$out" 'no valid JSON' "explains"
out=$(stdin | FAKE_MODE=limit bash "$S" 2>&1); code=$?; assert_eq 1 "$code" "reviewer unavailable = block"; assert_contains "$out" 'SKIP_REVIEW=1' "tells the human how to force"
rm -f "$FAKE_ARGS"; out=$(stdin | SKIP_REVIEW=1 FAKE_MODE=block bash "$S" 2>&1); code=$?
assert_eq 0 "$code" "SKIP_REVIEW=1 passes"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL SKIP_REVIEW called opencode"; FAILS=$((FAILS+1)); } || echo "  ok  SKIP_REVIEW never calls opencode"
assert_contains "$(cat docs/dev/reviews/skipped.log)" "$(git rev-parse HEAD)" "skipped range logged"
printf 'refs/heads/f %s refs/heads/f %s\n' 0000000000000000000000000000000000000000 "$(git rev-parse HEAD)" | bash "$S" >/dev/null 2>&1; assert_eq 0 "$?" "deletion-only push passes"
printf 'refs/heads/f %s refs/heads/f %s\n' "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 | FAKE_MODE=approve bash "$S" 2>&1 | grep -q 'range=4b825dc642cb6eb9a060e54bf8d69288fbee4904..' && echo "  ok  first push compared to the empty tree" || { echo "  FAIL first push base"; FAILS=$((FAILS+1)); }
git checkout -q base; git checkout -q -b same; rm -f "$FAKE_ARGS"; bash "$S" base >/dev/null 2>&1; code=$?
assert_eq 0 "$code" "empty diff passes"; [ -e "$FAKE_ARGS" ] && { echo "  FAIL empty diff called opencode"; FAILS=$((FAILS+1)); } || echo "  ok  empty diff skips opencode"
cd - >/dev/null; rm -rf "$W"; finish
```

- [ ] **Step 2: Run, expect FAIL** — `bash tests/review.test.sh` → "No such file".

- [ ] **Step 3: Agent** `template/.opencode/agents/reviewer.md`:

```markdown
---
description: Read-only adversarial reviewer. Can read, grep, glob and use the LSP; cannot edit, run commands, spawn agents or fetch the web.
mode: primary
model: opencode-go/deepseek-v4.1-flash
permission:
  edit: deny
  bash: deny
  task: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
---

You are the reviewer of record. The author is another model; trust nothing it claims. Read the diff you are given and the surrounding code (read, grep, LSP) before judging. Never edit anything. Never open `.env` or `.env.*`. Answer with the JSON object the prompt asks for and nothing else.
```

- [ ] **Step 4: Script** `plugins/core/scripts/review.sh` (then `cp` to `template/scripts/review.sh`):

```bash
#!/usr/bin/env bash
# Adversarial review of pushed ranges by the project's read-only `reviewer` opencode agent (DeepSeek on opencode go).
#   review.sh                  ranges from git's pre-push stdin (lefthook use_stdin) — only ranges touching sensitive paths; routine ones are skipped
#   review.sh <from> [<to>]    explicit range (to = HEAD) — always reviewed
#   review.sh --all            stdin ranges, every range reviewed (night shift)
# Blocks (exit 1) on verdict block, any high finding, no valid JSON, or reviewer unavailable. Never approves on failure.
# SKIP_REVIEW=1 git push (typed by a human, never by an agent): skips and logs the range to docs/dev/reviews/skipped.log; the night shift reviews it.
set -u
here=$(cd "$(dirname "$0")" && pwd)
runner=${OPENCODE_SH:-}
[ -n "$runner" ] || for c in "$here/opencode.sh" "${CLAUDE_PLUGIN_ROOT:-}/scripts/opencode.sh" ~/.claude/plugins/cache/*/campanha-dev-standards/*/plugins/core/scripts/opencode.sh ~/.claude/plugins/marketplaces/campanha-dev-standards/plugins/core/scripts/opencode.sh; do [ -f "$c" ] && { runner=$c; break; }; done
z=0000000000000000000000000000000000000000; empty=4b825dc642cb6eb9a060e54bf8d69288fbee4904
SENSITIVE='auth|session|permission|payment|stripe|billing|src/app/api/|/actions/|server/|migrations|prisma/schema|lefthook|\.claude/|\.opencode/|^scripts/'
all=; case ${1:-} in --all) all=1; shift;; esac
explicit=${1:+1}
ranges() {   # "from to" lines; trees compared directly, so rollbacks are reviewed too
  if [ -n "${1:-}" ]; then echo "$1 ${2:-HEAD}"; return; fi
  local lref lsha rref rsha seen=
  if [ ! -t 0 ]; then while read -r lref lsha rref rsha; do
    seen=1; [ "${lsha:-$z}" = "$z" ] && continue                                 # branch deletion
    [ "${rsha:-$z}" = "$z" ] && rsha=$(git merge-base origin/HEAD "$lsha" 2>/dev/null || git merge-base origin/main "$lsha" 2>/dev/null || echo "$empty")
    echo "$rsha $lsha"
  done; fi
  [ -n "$seen" ] || echo "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo origin/main) HEAD"
}
if [ "${SKIP_REVIEW:-}" = 1 ]; then
  mkdir -p docs/dev/reviews; ranges "$@" | sed "s/^/$(date -u +%FT%TZ) $(git config user.name 2>/dev/null || echo '?') /" >> docs/dev/reviews/skipped.log
  echo "review: skipped by SKIP_REVIEW=1 (logged in docs/dev/reviews/skipped.log; the night shift reviews it)"; exit 0
fi
rc=0
while read -r from to; do
  changed=$(git diff --name-only "$from" "$to" 2>/dev/null) || { echo "review: cannot diff $from $to" >&2; exit 1; }
  [ -n "$changed" ] || continue
  if [ -z "$explicit$all" ] && ! printf '%s\n' "$changed" | grep -qiE "$SENSITIVE"; then
    echo "review: routine diff $from..$to, skipped (the night shift reviews it; bash scripts/review.sh $from reviews now)"; continue; fi
  [ -f "$runner" ] || { echo "review: opencode.sh not found (install the core plugin or set OPENCODE_SH)" >&2; exit 1; }
  start=$(date +%s)
  out=$(OPENCODE_TIMEOUT=${REVIEW_TIMEOUT:-300} bash "$runner" "$PWD" reviewer <<EOF
Adversarial code review of the change between commits $from and $to in this repository.
Files changed:
$changed
Attack surface: authorization and tenant isolation, exposure or logging of personal data, injection (SQL, shell, HTML), secrets, input validation at API boundaries, data loss or irreversible migrations, broken edge cases, behaviour changed without a test.
Finding bar: only what would break, leak or be exploitable; ignore style. Each finding names the file and line you actually read, what breaks, and the minimal fix. Read surrounding code with your tools before deciding; never invent lines.
Output: one JSON object and nothing else, no code fences:
{"verdict":"approve"|"block","findings":[{"severity":"high"|"medium"|"low","file":"path","line":123,"what":"...","fix":"..."}]}
Verdict is block if any finding is high.
Diff:
$(git diff "$from" "$to" | head -c 200000)
EOF
  ); code=$?
  echo "review: range=$from..$to secs=$(( $(date +%s) - start ))"
  [ "$code" -eq 0 ] || { echo "$out"; echo "review: reviewer unavailable, push blocked. Fix the cause, or force it yourself: SKIP_REVIEW=1 git push" >&2; rc=1; continue; }
  json=$(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^[^{]*\({.*}\)[^}]*$/\1/p; /^{/p' | head -1 | jq -c . 2>/dev/null)   # ponytail: the JSON object on the first line that holds one, prose around it ignored
  [ -n "$json" ] || { echo "$out"; echo "review: no valid JSON verdict, blocked" >&2; rc=1; continue; }
  printf '%s' "$json" | jq -r '.findings[]? | "[\(.severity)] \(.file):\(.line) - \(.what) - \(.fix)"'
  verdict=$(printf '%s' "$json" | jq -r '.verdict'); high=$(printf '%s' "$json" | jq '[.findings[]? | select(.severity=="high")] | length')
  [ "$verdict" = approve ] && [ "$high" -eq 0 ] || { echo "review: blocked for $from..$to (verdict=$verdict, high findings=$high). Fix, commit, push again." >&2; rc=1; }
done < <(ranges "$@")
exit $rc
```

- [ ] **Step 5: lefthook** `template/lefthook.yml` pre-push becomes:

```yaml
pre-push:
  commands:
    typecheck:
      run: npx tsc --noEmit
    test:
      run: npm test --if-present -- --run
    review:   # sensitive paths only; routine diffs are reviewed by the night shift. SKIP_REVIEW=1 git push to force (humans only)
      use_stdin: true
      run: bash scripts/review.sh
```

(semgrep, trivy and docs commands removed; pre-commit unchanged.)

- [ ] **Step 6: Skill** `plugins/core/skills/review/SKILL.md`:

```markdown
---
name: review
description: Use when the pre-push review blocks, when the user asks for a review of a diff, or after writing a plan - a read-only DeepSeek reviewer (opencode go) judges; you fix. Never bypass it yourself.
---

# Adversarial review

Rule: the model that wrote the code never judges it alone.

- **Push blocked:** read the `[high]` lines in the hook output, fix, commit, push again. Max 3 rounds; then show the remaining findings to the user and stop. If the user wants to push anyway, tell them the exact command and let them type it: `SKIP_REVIEW=1 git push` (you may not run it).
- **On demand:** `bash scripts/review.sh <base>` reviews `<base>..HEAD` whatever the paths (routine diffs are otherwise left to the night shift).
- **Plans:** `bash "<base directory>/../../scripts/opencode.sh" "<repo>" reviewer <<'EOF'` … `EOF` with the plan pasted and the instruction "review this plan for gaps, risks and untestable steps; answer in prose". Apply findings you agree with; for each rejected finding add one line under `## Review notes` in the plan.
- Reviewer unavailable (no opencode, no login, quota): tell the user and stop.
```

- [ ] **Step 7: Deletions and references** — `git rm template/scripts/codex-review.sh template/scripts/docs-check.sh tests/codex-review.test.sh tests/docs-check.test.sh && git rm -r plugins/core/skills/codex-review`. In `tests/e2e.test.sh` replace lines 23–24 (`assert_exit 1 bash scripts/docs-check.sh HEAD~1` and the render check) with:

```bash
[ -f scripts/review.sh ] && [ -f .opencode/agents/reviewer.md ] && [ -f mise.toml ] && echo "  ok  copier rendered template" || { echo "  FAIL template not rendered"; FAILS=$((FAILS+1)); }
```

`grep -rn 'codex-review\|docs-check' plugins template tests copier.yml` → empty (README/CLAUDE/AGENTS are Task 6).

- [ ] **Step 8: `bash tests/run.sh` green. Commit** — `git add -A plugins/core/scripts/review.sh template/scripts template/.opencode/agents/reviewer.md template/lefthook.yml plugins/core/skills tests && git commit -m "feat(core): review.sh with a read-only DeepSeek reviewer replaces Codex in pre-push; docs-check leaves the push"`

---

### Task 4: `docs` agent, `nightly.sh`, server deploy files

**Files:**
- Create: `template/.opencode/agents/docs.md`, `plugins/core/scripts/nightly.sh`, `tests/nightly.test.sh`, `template/docs/dev/reviews/.gitkeep`, `deploy/nightly/nightly.service`, `deploy/nightly/nightly.timer`, `deploy/nightly/run-all.sh`, `deploy/nightly/README.md`

**Interfaces:**
- Consumes: `opencode.sh`, `review.sh --all` (Tasks 1, 3).
- Produces: `bash nightly.sh <repo-checkout>`: fetches origin, checks out `nightly/<UTC date>` from `origin/main`, reviews `.git/nightly-last..origin/main` (first run: last 20 commits), writes `docs/dev/reviews/<date>.md`, refreshes docs via the `docs` agent, commits, force-pushes the branch, stores the sha in `.git/nightly-last`. Exit 0 all steps ran (findings do not fail it); 1 a step could not run (tool missing, reviewer unavailable, push failed); 2 usage. No new commits: prints and exits 0.

- [ ] **Step 1: Write `tests/nightly.test.sh`**

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
S=$PWD/plugins/core/scripts/nightly.sh
W=$(mktemp -d); mkdir -p "$W/bin"
for t in semgrep trivy; do printf '#!/usr/bin/env bash\necho "%s: 1 finding"\nexit 1\n' "$t" > "$W/bin/$t"; chmod +x "$W/bin/$t"; done
printf '#!/usr/bin/env bash\necho "socket: ok"\n' > "$W/bin/npx"; chmod +x "$W/bin/npx"
cat > "$W/bin/opencode" <<'EOF'
#!/usr/bin/env bash
agent=; while [ $# -gt 0 ]; do case $1 in --agent) agent=$2; shift;; esac; shift; done
case $agent in
  reviewer) jq -nc '{type:"text",part:{text:"{\"verdict\":\"block\",\"findings\":[{\"severity\":\"medium\",\"file\":\"src/a.ts\",\"line\":1,\"what\":\"w\",\"fix\":\"f\"}]}"}}';;
  docs)     echo "- src/a.ts: a" >> docs/dev/architecture.md; jq -nc '{type:"tool_use",part:{tool:"edit"}}'; jq -nc '{type:"text",part:{text:"docs updated"}}';;
esac
echo '{"type":"step_finish","part":{"tokens":{"total":1},"cost":0}}'
EOF
chmod +x "$W/bin/opencode"; export PATH="$W/bin:$PATH"
git init -q --bare "$W/origin"; git clone -q "$W/origin" "$W/repo" 2>/dev/null; cd "$W/repo"; git checkout -q -b main
mkdir -p .opencode/agents docs/dev/reviews src scripts; cp "$OLDPWD"/template/.opencode/agents/{reviewer,docs}.md .opencode/agents/; cp "$OLDPWD"/template/scripts/review.sh scripts/
echo "# arch" > docs/dev/architecture.md; touch docs/dev/reviews/.gitkeep; echo a > src/a.ts
git add -A; git -c user.name=t -c user.email=t@t commit -qm init; git push -q origin main
export OPENCODE_SH=$OLDPWD/plugins/core/scripts/opencode.sh GIT_AUTHOR_NAME=n GIT_AUTHOR_EMAIL=n@n GIT_COMMITTER_NAME=n GIT_COMMITTER_EMAIL=n@n
day=$(date -u +%F)
out=$(bash "$S" "$W/repo" 2>&1); code=$?
assert_eq 0 "$code" "first run exits 0"
git fetch -q origin "nightly/$day" && echo "  ok  nightly branch pushed" || { echo "  FAIL branch not pushed"; FAILS=$((FAILS+1)); }
rep=$(git show "origin/nightly/$day:docs/dev/reviews/$day.md")
assert_contains "$rep" 'semgrep: 1 finding' "semgrep output in report"; assert_contains "$rep" 'trivy: 1 finding' "trivy output in report"; assert_contains "$rep" 'socket: ok' "socket output in report"
assert_contains "$rep" '\[medium\] src/a.ts:1 - w - f' "review findings in report"
assert_contains "$rep" 'zero-data-retention' "ZDR warning when never confirmed"
assert_contains "$(git show "origin/nightly/$day:docs/dev/architecture.md")" 'src/a.ts' "docs agent edits committed"
assert_eq "$(git rev-parse origin/main)" "$(cat .git/nightly-last)" "last reviewed sha stored"
out=$(bash "$S" "$W/repo" 2>&1); code=$?; assert_eq 0 "$code" "no new commits: exit 0"; assert_contains "$out" 'no new commits' "says so"
git checkout -q main; echo b >> src/a.ts; git commit -qam more; git push -q origin main; date -u +%F > docs/dev/reviews/.zdr-confirmed; git add -A; git commit -qm zdr; git push -q origin main
out=$(bash "$S" "$W/repo" 2>&1); code=$?; assert_eq 0 "$code" "second run exits 0"
rep=$(git show "origin/nightly/$day:docs/dev/reviews/$day.md"); printf '%s' "$rep" | grep -q 'zero-data-retention' && { echo "  FAIL ZDR warning despite fresh confirmation"; FAILS=$((FAILS+1)); } || echo "  ok  no ZDR warning when confirmed"
git checkout -q main; echo c >> src/a.ts; git commit -qam c; git push -q origin main
rm "$W/bin/semgrep"; out=$(bash "$S" "$W/repo" 2>&1); code=$?; assert_eq 1 "$code" "missing tool: exit 1"; assert_contains "$(git show "origin/nightly/$day:docs/dev/reviews/$day.md")" 'semgrep: missing' "missing tool named in report"
assert_exit 2 bash "$S" /nonexistent
cd - >/dev/null; rm -rf "$W"; finish
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Agent** `template/.opencode/agents/docs.md`:

```markdown
---
description: Night-shift documentation refresh. Writes only under docs/ and CHANGELOG.md; no shell, no subagents, no web.
mode: primary
model: opencode-go/deepseek-v4.1-flash
permission:
  bash: deny
  task: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
  edit:
    "*": deny
    "docs/**": allow
    "CHANGELOG.md": allow
---

You keep the living documentation current from a list of changed files. English only. Edit existing sections in place; never append history to current-state files; never invent behaviour you did not read in the code.

Map each changed path and update the target:
- schema, migrations, `prisma/`, `supabase/` → `docs/dev/reference/data-model.md`
- `.env.example`, env vars → `docs/dev/reference/env-vars.md`
- routes, API handlers, server actions → `docs/dev/reference/endpoints.md`
- external services, workers, crons → `docs/dev/reference/integrations.md`
- `Dockerfile`, compose, `deploy/` → `docs/dev/how-to/deploy.md`
- auth, roles, personal data, security headers → `docs/dev/explanation/security.md`, `docs/product/roles.md`
- UI screens, user-visible behaviour → `docs/product/features/<feature>.md` (what, who, steps, rules); add `> Screenshot stale: <screen>` under the heading of a changed screen
Then add one line per user- or developer-visible change under `## [Unreleased]` in `CHANGELOG.md` (Added / Changed / Removed / Fixed / Security). Never paste commit messages. Never open `.env` or `.env.*`.
End with: `Summary:` one line, `Files:` one `- path — why` line per file you changed.
```

- [ ] **Step 4: Script** `plugins/core/scripts/nightly.sh`:

```bash
#!/usr/bin/env bash
# Night shift for one adopted repo checkout (runs on the server from a systemd timer; see deploy/nightly/).
#   nightly.sh <repo>   needs: git with push rights, opencode login, semgrep, trivy, npx (Socket), jq.
# Reviews everything pushed to origin/main since the last run, runs the scanners, refreshes docs with the `docs` agent,
# commits to branch nightly/<date> and pushes only that branch. Report: docs/dev/reviews/<date>.md.
# Exit 0 every step ran (findings do not fail the run) · 1 a step could not run (tool missing, reviewer unavailable, push failed) · 2 usage.
set -u
repo=${1:-}; git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: nightly.sh <repo>" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); export OPENCODE_SH=${OPENCODE_SH:-$here/opencode.sh}
cd "$repo" || exit 2
day=$(date -u +%F); branch=nightly/$day; report=docs/dev/reviews/$day.md; state=$(git rev-parse --git-dir)/nightly-last
git fetch -q origin main && git checkout -q -B "$branch" origin/main || { echo "nightly: fetch or checkout failed" >&2; exit 1; }
to=$(git rev-parse origin/main); from=$(cat "$state" 2>/dev/null || git rev-parse "origin/main~20" 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)
[ "$from" != "$to" ] || { echo "nightly: no new commits since $from"; exit 0; }
mkdir -p docs/dev/reviews; rc=0
step() {   # step <name> <command...>: appends a section; a missing tool is named and fails the run, tool findings do not
  echo; echo "## $1"; echo; shift
  if ! command -v "$1" >/dev/null; then echo "$1: missing"; rc=1; return; fi
  echo '```'; "$@" 2>&1 | tail -n 200; echo '```'
}
{
  echo "# Night shift $day"; echo; echo "Range: \`$from..$to\` ($(git rev-list --count "$from..$to" 2>/dev/null || echo '?') commits)"
  zdr=$(cat docs/dev/reviews/.zdr-confirmed 2>/dev/null || echo 1970-01-01)
  [ $(( ( $(date +%s) - $(date -d "$zdr" +%s 2>/dev/null || echo 0) ) / 86400 )) -le 35 ] || { echo; echo "> WARNING: opencode go zero-data-retention for DeepSeek last confirmed $zdr. Check https://opencode.ai/docs/go/ and write today's date to docs/dev/reviews/.zdr-confirmed."; }
  echo; echo "## Pushed without review"; echo; { cat docs/dev/reviews/skipped.log 2>/dev/null || true; } | grep . || echo "none"
  step semgrep semgrep scan --config p/default --error --quiet --metrics=off
  step trivy trivy fs --scanners vuln,secret --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 --quiet --skip-dirs node_modules --skip-files ".env*,**/.env*" .
  step socket npx --yes socket scan create .
  echo; echo "## Review"; echo; echo '```'
  printf 'refs/heads/main %s refs/heads/main %s\n' "$to" "$from" | bash scripts/review.sh --all 2>&1; echo '```'
} > "$report" 2>&1
grep -q 'reviewer unavailable\|opencode.sh not found' "$report" && rc=1
: > docs/dev/reviews/skipped.log 2>/dev/null || true
out=$(bash "$OPENCODE_SH" "$PWD" docs <<EOF
Refresh the documentation for these files changed between $from and $to:
$(git diff --name-only "$from" "$to")
Diff (for context, read the files themselves when unsure):
$(git diff "$from" "$to" | head -c 150000)
EOF
); d=$?; { echo; echo "## Docs"; echo; echo '```'; echo "$out" | tail -n 60; echo '```'; } >> "$report"; [ $d -eq 0 ] || rc=1
git add -A docs CHANGELOG.md 2>/dev/null; git -c user.name="night shift" -c user.email="nightly@localhost" commit -qm "docs: night shift $day" 2>/dev/null || true
git push -q -f origin "$branch" || { echo "nightly: push failed" >&2; rc=1; }
[ $rc -eq 0 ] && echo "$to" > "$state"
echo "nightly: $branch pushed, report $report, rc=$rc"; exit $rc
```

Note for the implementer: the `socket` step's exact CLI (`npx --yes socket scan create` vs `npx --yes socket`) is not verified offline; keep the first form that prints without a login prompt, and if neither runs unattended without an API key, replace the step with `step socket npx --yes socket --version` and leave a comment `# ponytail: Socket needs SOCKET_API_KEY; wire the real scan when the team has one`. The test only asserts that the fake `npx` output lands in the report.

- [ ] **Step 5: Deploy files** — `template/docs/dev/reviews/.gitkeep` (empty). `deploy/nightly/run-all.sh`:

```bash
#!/usr/bin/env bash
# Runs nightly.sh for every checkout listed in /etc/campanha/repos (one absolute path per line; file is server-local, never committed).
set -u
list=${1:-/etc/campanha/repos}; here=$(cd "$(dirname "$0")" && pwd); rc=0
while read -r repo; do [ -n "$repo" ] && [ "${repo#\#}" = "$repo" ] || continue; bash "$here/../../plugins/core/scripts/nightly.sh" "$repo" || rc=1; done < "$list"
exit $rc
```

`deploy/nightly/nightly.service`:

```ini
[Unit]
Description=campanha night shift: review, scan and refresh docs of adopted repos
[Service]
Type=oneshot
User=nightly
Environment=PATH=/home/nightly/.local/bin:/home/nightly/.opencode/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash /home/nightly/campanha-dev-standards/deploy/nightly/run-all.sh
```

`deploy/nightly/nightly.timer`:

```ini
[Unit]
Description=campanha night shift, 03:00 UTC daily
[Timer]
OnCalendar=*-*-* 03:00:00 UTC
Persistent=true
[Install]
WantedBy=timers.target
```

`deploy/nightly/README.md` (≤ 30 lines): create user `nightly` on box-one; `mise` + `mise use -g semgrep trivy jq node@24` for that user; install opencode (`curl -fsSL https://opencode.ai/install | bash`) and `opencode auth login` with the **dedicated** opencode go account; one read/write deploy key per repo in `~/.ssh` with a `Host` alias; clone `campanha-dev-standards` to `~/campanha-dev-standards` and each app to `~/repos/<name>`; write `/etc/campanha/repos`; `cp deploy/nightly/nightly.{service,timer} /etc/systemd/system/ && systemctl enable --now nightly.timer`; check with `systemctl list-timers nightly.timer` and `journalctl -u nightly`; monthly: confirm the DeepSeek row on https://opencode.ai/docs/go/ still says 0 days / not used, then commit today's date to `docs/dev/reviews/.zdr-confirmed` in each repo. lefthook is not installed on the server checkouts, so the nightly push runs no hooks.

- [ ] **Step 6: `bash tests/run.sh` green (assets test also runs `bash -n` on the new scripts). Commit** — `git add -A plugins/core/scripts/nightly.sh template/.opencode/agents/docs.md template/docs/dev/reviews tests/nightly.test.sh deploy && git commit -m "feat(core): nightly.sh night shift with docs agent; systemd deploy files"`

---

### Task 5: `rescue` skill, `handoff` as a prompt, hook rules for `SKIP_REVIEW` anchored to git commands

**Files:**
- Create: `plugins/core/skills/rescue/SKILL.md`
- Modify: `plugins/core/skills/handoff/SKILL.md` (whole file), `plugins/core/hooks/block-unsafe-bash.sh:6-7`, `tests/hooks-bash.test.sh`

**Interfaces:**
- Consumes: `worker.sh`, `review.sh` (Tasks 2, 3).
- Produces: hook denies an agent-written `git`/`lefthook` command carrying `--no-verify`, `--no-gpg-sign` or `core.hooksPath`, and any command segment that sets `SKIP_REVIEW=1`, `LEFTHOOK=0` or `LEFTHOOK_EXCLUDE` (inline or `export`); it no longer denies those strings inside quotes, heredocs or commit messages.

- [ ] **Step 1: Update `tests/hooks-bash.test.sh`** — replace the block from `deny  block-unsafe-bash.sh 'git commit -m x --no-verify'` through `deny  block-unsafe-bash.sh 'git push --no-verify'` (second occurrence) with:

```bash
deny  block-unsafe-bash.sh 'git commit -m x --no-verify'
deny  block-unsafe-bash.sh 'git push --no-verify'
deny  block-unsafe-bash.sh 'cd app && git push origin main --no-verify'
deny  block-unsafe-bash.sh 'git -c core.hooksPath=/dev/null push'
deny  block-unsafe-bash.sh 'git config core.hooksPath /dev/null'
deny  block-unsafe-bash.sh 'LEFTHOOK=0 git push'
deny  block-unsafe-bash.sh 'SKIP_REVIEW=1 git push'
deny  block-unsafe-bash.sh 'cd app && SKIP_REVIEW=1 git push origin main'
deny  block-unsafe-bash.sh 'export SKIP_REVIEW=1'
deny  block-unsafe-bash.sh 'export LEFTHOOK=0; git push'
deny  block-unsafe-bash.sh 'LEFTHOOK_EXCLUDE=review git push'
deny  block-unsafe-bash.sh 'env SKIP_REVIEW=1 git push'
allow block-unsafe-bash.sh 'git commit -m "docs: explain why --no-verify is denied"'
allow block-unsafe-bash.sh 'echo "humans may run SKIP_REVIEW=1 git push"'
allow block-unsafe-bash.sh 'grep -rn "no-verify" plugins'
allow block-unsafe-bash.sh 'git push origin main'
allow block-unsafe-bash.sh 'git commit -m x'
```

Keep the dotenv, prisma and supabase cases as they are.

- [ ] **Step 2: Run, expect FAIL** on the three new `allow` cases and the `export`/`env` denies.

- [ ] **Step 3: Implement** — replace lines 6–7 of `plugins/core/hooks/block-unsafe-bash.sh` with:

```bash
# Gate bypasses, anchored to a real git/lefthook invocation in the same command segment (quotes, heredocs and commit messages do not match).
seg='(^|[;&|(][[:space:]]*|\bsudo[[:space:]]+|\benv[[:space:]]+)([A-Z_]+=[^[:space:]]*[[:space:]]+)*'
printf '%s' "$cmd" | grep -Eq -- "${seg}(git|lefthook|npx[[:space:]]+lefthook)[[:space:]][^;&|\"']*(--no-verify|--no-gpg-sign|core\.hooksPath)" \
  && deny "Git hooks are the quality gate. Never bypass them; fix what the hook reports."
printf '%s' "$cmd" | grep -Eq -- "${seg}(export[[:space:]]+)?(SKIP_REVIEW=1|LEFTHOOK=0|LEFTHOOK_EXCLUDE=)" \
  && deny "Skipping the review is the human's call, not yours. Tell the user why it blocked and the exact command they can type themselves."
```

- [ ] **Step 4: Rescue skill** `plugins/core/skills/rescue/SKILL.md`:

```markdown
---
name: rescue
description: Use when you are stuck on a task (same failure after two attempts, or no idea where the bug is) - a fresh DeepSeek session (opencode go) gets the problem and tries; you verify. Whoever wrote the code never grades it.
---

# Rescue

1. Commit or stash your own changes (the worker refuses a dirty tree).
2. Call the worker with a rescue brief, one problem per call:

       bash "<base directory>/../../scripts/worker.sh" "<absolute repo path>" <<'TASK_END'
       Outcome: <the test or behaviour that must pass>
       Problem: <what fails, in one paragraph; what you tried and why it did not work>
       Command: <the failing command>
       Output: <its output, trimmed to the relevant 40 lines>
       Files: <files involved; the only files it may change>
       Keep: <what must not change>
       TASK_END

3. Never trust "done": run the failing command yourself and read `git diff`. If the diff touches auth, API handlers, db or the gates, run `bash scripts/review.sh HEAD~1` (or the base commit) before committing.
4. Second failure → tell the user what both attempts found and stop. If the Codex plugin is installed the user may try `/codex:rescue`; that is their call, not yours.
```

- [ ] **Step 5: Handoff skill** `plugins/core/skills/handoff/SKILL.md`:

```markdown
---
name: handoff
description: Use at the end of a work block, before /clear, when the quota is about to run out, or when the user says "handoff" - invoke as `core:handoff` - outputs a paste-ready prompt so the next session (Claude, Codex or opencode) continues without re-reading history. Writes a file only when asked.
---

# Handoff

Output one fenced block the user can paste into any tool, second person, English, facts only (branch, failing test, file paths, no narrative). Do not ask what format they want. Do not write a file unless the user says "handoff em ficheiro" / "handoff file".

    You are continuing work in <repo> on branch <branch>. Read AGENTS.md and docs/dev/architecture.md first.
    Was doing: <one or two lines; link the spec/plan being executed>
    Left half-done: <one or two lines; failing test and path if any>
    Do not: <one or two lines>
    Next step: <one line>. Start there.
    git status --short:
    <output>
    git diff --stat <upstream>...HEAD:
    <output>

When a file is requested: also write `docs/dev/handoffs/YYYY-MM-DD-<author>.md` (author = git `user.name`, lowercase) with the same content under the heading `# Handoff YYYY-MM-DD — <author>`, and commit it with `docs: handoff YYYY-MM-DD`.
```

- [ ] **Step 6: `bash tests/run.sh` green (assets test parses the new skill). Commit** — `git add -A plugins/core/skills plugins/core/hooks/block-unsafe-bash.sh tests/hooks-bash.test.sh && git commit -m "feat(core): rescue skill; handoff outputs a prompt; hook denies SKIP_REVIEW and anchors bypass rules to git commands"`

Write the commit message with the Write tool into a temp file in the scratchpad and use `git commit -F <file>` if the hook denies the message text.

---

### Task 6: Template, README, adopt, versions, changelog

**Files:**
- Modify: `template/mise.toml`, `template/CLAUDE.md`, `template/AGENTS.md`, `README.md`, `plugins/core/commands/adopt.md`, `plugins/core/agents/doc-keeper.md:3`, `.claude-plugin/marketplace.json`, `plugins/core/.claude-plugin/plugin.json`, `CHANGELOG.md`, `template/.claude/settings.json` (Codex plugin stays, comment-free), `tests/assets.test.sh` (no change expected; run it)

- [ ] **Step 1: `template/mise.toml`** — delete the line `"npm:@openai/codex" = "latest"`. Add a comment line at the top: `# opencode is not installable by mise: curl -fsSL https://opencode.ai/install | bash, then opencode auth login (opencode go).`

- [ ] **Step 2: `template/CLAUDE.md`** — replace the whole `# Claude-specific` list with:

```markdown
# Claude-specific
- Small tasks (bug, UI tweak): no ritual. Do it, run the test, commit. Brainstorm → plan → review only when the user asks or the change crosses modules.
- Gruntwork (scoped edits, searches): `core:worker` skill (DeepSeek on opencode go); exit 3 → Sonnet subagent (`Agent` tool, `model: sonnet`). You run the tests, trimmed (`| tail -40`).
- Stuck: `core:rescue` skill; verify with `git diff` and the failing command before trusting "done".
- Review: pre-push runs `scripts/review.sh` on sensitive diffs only (auth, API, db, gates) and blocks; the night shift reviews the rest. When it blocks: `core:review` skill. Never bypass; the human can type `SKIP_REVIEW=1 git push` themselves.
- Docs: the night shift refreshes them; run the `doc-keeper` agent (mode diff) only when the user asks or a feature ships.
- Usage: subagents run on Haiku by default (`CLAUDE_CODE_SUBAGENT_MODEL`); `model: sonnet` only for the worker fallback and visual checks. Never Agent Teams. Do not enable the Codex plugin's review gate.
- Visual verification: a Sonnet subagent drives headless Chrome via the Playwright CLI (viewports 1440×900 and 390×844), reads the screenshots, then deletes them.
- Ponytail level lite: smallest change at the right level — colours, components and business rules are fixed at the source, never in the screen.
- End of a work block or before the quota runs out: `core:handoff` skill (always the qualified name); it prints a prompt to paste into the next session, any tool.
```

- [ ] **Step 3: `template/AGENTS.md`** — line 16: `- Without Claude: \`opencode run --agent worker --auto "<task>"\` from the repo (agent in \`.opencode/agents/\`, no shell).` Line 33: `- Handoffs arrive as a pasted prompt; \`docs/dev/handoffs/\` holds only the ones written on request.` Gates section:

```markdown
## Gates (do not bypass)
- commit: gitleaks, eslint (incl. design lint).
- push: typecheck, tests; `scripts/review.sh` (DeepSeek, read-only) when the diff touches auth, API handlers, db or the gates.
- night shift (server): semgrep, trivy, Socket, review of everything pushed, docs refresh → branch `nightly/<date>` and `docs/dev/reviews/<date>.md`. Read the latest report at session start.
- Humans may force a push with `SKIP_REVIEW=1 git push` (logged, reviewed at night). Agents may not.
```

- [ ] **Step 4: `README.md`** — Install block becomes:

```
    curl https://mise.run | sh                           # mise installs the pinned tools per repo
    curl -fsSL https://opencode.ai/install | bash        # opencode; then: opencode auth login → OpenCode Go (one $10 subscription per dev)
    # optional: Codex CLI + the openai/codex-plugin-cc plugin for manual /codex:rescue (review gate off)
```

"What you get" bullets: replace the push-gates bullet, the usage bullet, the worker bullet and the handoff bullet with:

```markdown
- Push gates (seconds): typecheck, tests, and a read-only DeepSeek review (`scripts/review.sh`, JSON findings, blocks on `high`) only when the diff touches auth, API handlers, db or the gates. Humans can force with `SKIP_REVIEW=1 git push`; agents cannot.
- Night shift (`scripts/nightly.sh`, systemd timer on your server, see `deploy/nightly/`): semgrep, trivy, Socket, full review and a docs refresh over everything pushed that day → branch `nightly/<date>` + `docs/dev/reviews/<date>.md`.
- Usage economy: all gruntwork, review and docs run on opencode go (DeepSeek V4.1 Flash), not on the Claude subscription; subagents on Haiku; no Agent Teams; Codex optional.
- `core:worker`, `core:review`, `core:rescue` skills over one runner (`scripts/opencode.sh`, `opencode run --format json`); three project agents with real permission limits (`worker`, `reviewer`, `docs`).
- `core:handoff` prints a prompt to paste into the next session (any tool).
```

Remove the "Pin the Codex plugin version" line and the two `/plugin … codex` lines from the required install list (keep them in the optional comment). Add the v3 spec to the Designs line.

- [ ] **Step 5: `plugins/core/commands/adopt.md`** — step 2 also says: "`.opencode/agents/{worker,reviewer,docs}.md` and `scripts/review.sh` come from the template; `opencode auth login` once per dev." Step 6: replace "`lefthook run pre-push` (it will call Codex; expect a review)" with "`lefthook run pre-push` (review runs only if the adopt diff touches sensitive paths)". Add step 8: "Server: add the repo's checkout path to `/etc/campanha/repos` on box-one (see `deploy/nightly/README.md`) so the night shift covers it." `plugins/core/agents/doc-keeper.md` line 3 description: "Keeps docs/dev (builders) and docs/product (users) current. Mode diff on request or when a feature ships (the night shift covers routine changes); mode bootstrap when adopting an existing repo; mode consolidate for the weekly drift check."

- [ ] **Step 6: Versions and changelog** — `plugins/core/.claude-plugin/plugin.json` version `0.3.0`; `.claude-plugin/marketplace.json` plugin description: "Two Bash hooks, doc-keeper agent, worker / review / rescue / handoff skills over opencode go (DeepSeek), /adopt and /docs-consolidate commands; project template via copier (lefthook gates, night-shift scripts, mise.toml, docs tree)." `CHANGELOG.md`: move the current `[Unreleased]` entries into a new `## [0.3.0] - 2026-09-15` with:

```markdown
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
```

- [ ] **Step 7: `bash tests/run.sh` green; `grep -rn -i 'codex' plugins template README.md copier.yml` shows only the optional mentions (settings plugin entry, README optional line, CLAUDE.md review-gate line, rescue skill last line, adopt). `grep -rn 'deepseek-worker\|docs-check\|codex-review' plugins template tests README.md copier.yml` → empty. Commit** — `git commit -am "docs: v3 release notes, README, templates and version 0.3.0"`

---

## Review notes

(added during plan review)
