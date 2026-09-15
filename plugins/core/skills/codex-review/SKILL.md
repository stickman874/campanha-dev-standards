---
name: codex-review
description: Use after writing a plan, and when the pre-push `review` step blocks - Codex (another vendor's model) reviews; you fix. The pre-push hook runs it on every push automatically.
---

# Codex adversarial review

The rule: the model that wrote the code never judges it alone.

- **Diffs:** nothing to invoke. `lefthook` `pre-push` runs `scripts/codex-review.sh`, which picks the Codex model by diff sensitivity and blocks on `VERDICT: block`. When it blocks: read the `[high]` findings in the hook output, fix, commit, push again. Max 3 rounds; then show the remaining findings to the user and stop.
- **Plans, before implementation:** `codex review - <<'EOF'` … `EOF` with the plan path and the instruction "review this plan for gaps, risks and untestable steps" as the stdin text (`-c model="gpt-6-astra" -c model_reasoning_effort="medium"`). Apply findings you agree with; for each rejected finding add one line under `## Review notes` in the plan.
- Codex unavailable (no `codex`, no login, no credits): tell the user and stop. Do not bypass the hook.
