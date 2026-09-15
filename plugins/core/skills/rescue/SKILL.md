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
