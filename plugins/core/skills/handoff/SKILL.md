---
name: handoff
description: Use at the end of a work block, before /clear, when the quota is about to run out, or when the user says "handoff" - invoke as `core:handoff` (bare `handoff` may resolve to another plugin) - outputs a paste-ready prompt so the next session (Claude, Codex or opencode) continues without re-reading history. Writes a file only when asked.
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
