---
name: worker
description: Use to hand a well-scoped edit or code search to the cheap no-shell worker instead of a Sonnet subagent - DeepSeek V4.1 Flash on opencode go (a script), or on a Claude-only repo the Haiku `worker` subagent. On DEEPSEEK_UNAVAILABLE or a failed Haiku run, redo the task with a Sonnet subagent.
---

# Worker

Backend comes from the repo: `backend: claude` in `.copier-answers.yml` → section **Claude-only repo** below; otherwise DeepSeek on opencode go:

    bash "<base directory>/../../scripts/worker.sh" "<absolute repo path>" <<'TASK_END'
    Outcome: the behaviour or artifact that must exist
    Files: exact files to read first, and the only files it may change
    Keep: behaviour and files that must stay as they are
    Config: any non-secret values it needs (it has no shell and no .env)
    TASK_END

Bash timeout 660000 ms. Commit or stash your own changes first (it refuses a dirty tree). The quoted heredoc keeps backticks and `$(...)` from running in your shell. One outcome per call.

Parallel workers: one `git worktree add ../<repo>-<task> -b <task>` per task, pass each worktree path as the repo. Each starts clean, so the dirty-tree rule holds and each diff stays attributable. Merge or cherry-pick when they return, then `git worktree remove`.

After it returns:
- Exit 3 `DEEPSEEK_UNAVAILABLE` / `CLAUDE_UNAVAILABLE`: read the partial output and `git status`. Every change is the worker's: keep or revert (`git checkout -- <file>`, `git clean -f <file>`). Give the task to a Sonnet subagent (`Agent` tool, `model: sonnet`) with that state described. Retry the worker once at the next milestone, never in a loop.
- Exit 4 "wrote nothing": the worker read but did not edit. Sharpen `Files:` and `Outcome:` and call once more; then Sonnet.
- Exit 0: check `--- claimed but unchanged` (files it says it edited but git does not see: treat the claim as false), read the diff, run the relevant test file yourself, trimmed: `npm test -- --run <file> 2>&1 | tail -40`. One failure → one more call with the error pasted under the same task, or fix it yourself if small. Still failing → Sonnet or you.
- `SensitiveSeen` other than `none`: check nothing secret landed in files or output; if it did, rotate it and tell the user.
- It never commits; you do.

## Claude-only repo

`Agent` tool, `subagent_type: "worker"` (project agent `.claude/agents/worker.md`: Haiku, no shell, no web), prompt = the same `Outcome / Files / Keep / Config` brief. Commit or stash your own changes first, so every change in `git status` afterwards is the worker's. Parallel workers: one call per task in the same message, each with `isolation: "worktree"`; merge or cherry-pick when they return.

After it returns (the checks the opencode script makes, made by you):
- Compare its `Files:` lines with `git status --short`: a file it claims but git does not show was not changed; treat the claim as false. It read but changed nothing → sharpen `Files:` and `Outcome:` and call once more; then Sonnet.
- Read `git diff`, run the relevant test file yourself, trimmed: `npm test -- --run <file> 2>&1 | tail -40`. One failure → one more call with the error pasted; still failing → a Sonnet subagent (`Agent` tool, `model: sonnet`) or you.
- Rate limit or error: keep or revert its partial changes, then Sonnet. `SensitiveSeen` and commits: as above.
