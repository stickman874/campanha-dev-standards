---
name: review
description: Use when the pre-push review blocks, when the user asks for a review of a diff, or after writing a plan - a read-only reviewer judges (DeepSeek on opencode go, or Sonnet on a Claude-only repo); you fix. Never bypass it yourself.
---

# Adversarial review

Rule: the model that wrote the code never judges it alone.

- **Push blocked:** read the `[high]` lines in the hook output, fix, commit, push again. Max 3 rounds; then show the remaining findings to the user and stop. If the user wants to push anyway, tell them the exact command and let them type it: `SKIP_REVIEW=1 git push` (you may not run it).
- **On demand:** `bash scripts/review.sh <base>` reviews `<base>..HEAD` whatever the paths (routine diffs are otherwise left to the night shift).
- **Plans:** `bash "<base directory>/../../scripts/opencode.sh" "<repo>" reviewer <<'EOF'` … `EOF` with the plan pasted and the instruction "review this plan for gaps, risks and untestable steps; answer in prose". Apply findings you agree with; for each rejected finding add one line under `## Review notes` in the plan.
- Reviewer unavailable (no opencode/claude, no login, quota): tell the user and stop.
