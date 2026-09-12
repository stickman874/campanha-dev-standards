---
name: codex-review
description: Use before any git push, and after writing a plan - runs Codex adversarial review on the current diff or plan, fixes findings, and records the review marker the push gate requires.
---

# Codex review (independent second opinion)

Rule: the model that wrote the code never judges it alone. Codex reviews; you fix.

`/codex:adversarial-review` is user-only (`disable-model-invocation`), so call the codex runtime directly:

    CODEX="$(jq -r '.plugins["codex@openai-codex"][0].installPath' ~/.claude/plugins/installed_plugins.json)/scripts/codex-companion.mjs"
    test -f "$CODEX" || { echo "codex plugin not installed: $CODEX"; exit 1; }

This reads the installed (pinned) version, not the newest cached one, so a rollback is honoured.

## On a plan (before implementation)
1. Run `node "$CODEX" adversarial-review --wait "review the plan in <plan path>"`.
2. Apply every finding you agree with to the plan. For findings you reject, add one line under a `## Review notes` section in the plan saying why.

## On a diff (before push)
1. Ensure everything is committed (`git status` clean). The gate keys the marker to HEAD.
2. Run `node "$CODEX" adversarial-review --wait`.
3. Fix real findings, commit again, and re-run step 2 until Codex reports nothing material. Max 3 rounds; after that list remaining findings to the user and stop.
4. Record the marker for the final HEAD:

    mkdir -p "$(git rev-parse --git-dir)/campanha" && touch "$(git rev-parse --git-dir)/campanha/reviewed-$(git rev-parse HEAD)"

5. Then invoke the `doc-keeper` agent in mode push (it writes the docs marker). Only then push.

Never touch the marker without running the review. If Codex is unavailable (no credit, CLI down), tell the user and stop; do not push.
