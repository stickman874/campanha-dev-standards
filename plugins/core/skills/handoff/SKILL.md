---
name: handoff
description: Use at the end of a work block, before /clear, or when the user says "handoff" - invoke as `core:handoff` (bare `handoff` may resolve to another plugin) - writes a dated 4-line handoff note so the next person or session (human or AI) can continue without re-reading history.
---

# Handoff

Write `docs/dev/handoffs/YYYY-MM-DD-<author>.md` (author = git `user.name`, lowercase; if the file exists today, append a new `## HH:MM` section).

Exactly these four headings, one to three lines each, in English:

```
# Handoff YYYY-MM-DD — <author>

## Was doing
## Left half-done
## Do not
## Next step
```

Rules: facts only (branch name, failing test, file paths); no narrative. Link the spec/plan being executed. Commit with `docs: handoff YYYY-MM-DD`. Do not push (the gate would require review); the next push carries it.

At session start, read the newest file in `docs/dev/handoffs/` before anything else.
