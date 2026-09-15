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
