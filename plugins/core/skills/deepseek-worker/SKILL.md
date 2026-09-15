---
name: deepseek-worker
description: Use to hand a well-scoped edit or code search to DeepSeek V4.1 Flash (cheap, fast, no shell) instead of a Sonnet subagent. Runs a script, not a subagent; if it prints DEEPSEEK_UNAVAILABLE, redo the task with a Sonnet subagent.
---

# DeepSeek worker

A script drives opencode's no-shell `deepseek-worker` agent, so no model relays (or quietly does) the task. Run it with a Bash timeout of 600000 ms, from any directory. The script lives two levels up from this skill's base directory:

    bash "<base directory>/../../scripts/deepseek.sh" run "<absolute repo path>" <<'DEEPSEEK_TASK_END'
    <task packet>
    DEEPSEEK_TASK_END

The quoted heredoc keeps backticks and `$(...)` in the task from running in your shell. Pick another delimiter if the task contains that exact line.

## Task packet

The worker knows nothing about this conversation. Fill every line:

    Outcome: the behaviour or artifact that must exist
    Inputs: exact files to read first
    Scope: the only files it may change
    Preserve: behaviour and files that must stay as they are
    Acceptance: the normal case and one boundary case

One outcome per call. Split anything bigger.

## After it returns

- `DEEPSEEK_UNAVAILABLE` (exit 3): it may have stopped halfway. Read the partial output and `git status` it prints; keep or revert (`git checkout -- <file>`) those changes, then give the task to a Sonnet subagent with that state described. Retry DeepSeek once at the next milestone, never in a loop.
- Otherwise read the diff yourself and run the tests or typecheck it lists under `Verify:`. It cannot run them.
- `Partial: true` or a failing check: one correction round with the exact failure. If it fails again, use a Sonnet subagent or do it yourself.
- `SensitiveSeen` other than `none`: check that nothing secret landed in files or output. If a real secret was exposed, rotate it and tell the user.
- It never commits; you do. Add the trailer `Worker: deepseek` to every commit that contains its changes, so `codex-review` sends that diff to Codex instead of letting DeepSeek review its own work.
