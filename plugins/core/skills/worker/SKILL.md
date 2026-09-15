---
name: worker
description: Use to hand a well-scoped edit or code search to DeepSeek V4.1 Flash (cheap, no shell) instead of a Sonnet subagent. Runs a script, not a subagent; if it prints DEEPSEEK_UNAVAILABLE, redo the task with a Sonnet subagent.
---

# DeepSeek worker

    bash "<base directory>/../../scripts/worker.sh" "<absolute repo path>" <<'TASK_END'
    Outcome: the behaviour or artifact that must exist
    Files: exact files to read first, and the only files it may change
    Keep: behaviour and files that must stay as they are
    TASK_END

Bash timeout 660000 ms. Commit or stash your own changes first (`run` refuses a dirty tree). The quoted heredoc keeps backticks and `$(...)` from running in your shell. One outcome per call.

After it returns:
- `DEEPSEEK_UNAVAILABLE` (exit 3): read the partial output and `git status`. Every change is the worker's: keep or revert (`git checkout -- <file>`, `git clean -f <file>`). Give the task to a Sonnet subagent with that state described. Retry DeepSeek once at the next milestone, never in a loop.
- Otherwise read the diff and run the relevant test file yourself, output trimmed: `npm test -- --run <file> 2>&1 | tail -40`. One failure → one more `worker.sh` call with the error pasted under the same task, or fix it yourself if small. Still failing → Sonnet subagent or you.
- `SensitiveSeen` other than `none`: check nothing secret landed in files or output; if it did, rotate it and tell the user.
- It never commits; you do.
