---
name: codex-review
description: Use before any git push, and after writing a plan - independent review by another vendor's model (DeepSeek for routine diffs, Codex for sensitive diffs and plans), fixes findings, and records the review marker the push gate requires.
---

# Independent review (second opinion)

Rule: the model that wrote the code never judges it alone. Another vendor's model reviews; you fix.

## Who reviews

| What | Reviewer | If the reviewer is unavailable |
| --- | --- | --- |
| A diff touching authentication, permissions, personal data, API handlers, uploads, payments, external integrations, secrets, or the gates themselves (hooks, guard, `.claude/settings.json`, `lefthook.yml`, CI) | Codex, required | Tell the user and stop. No push. |
| A diff containing DeepSeek-written code: any commit in `git log <base>..HEAD --grep='^Worker: deepseek'` | Codex, required (DeepSeek never reviews its own work) | Tell the user and stop. No push. |
| Any other diff | DeepSeek | Codex |
| A plan, before implementation | Codex | DeepSeek |

Sensitive or not is your judgment, with the same scope as `security-posture`. `git diff --name-only <base>...HEAD` helps. When in doubt, treat it as sensitive.

`<base>` is what the branch will be pushed onto: `git rev-parse --abbrev-ref @{upstream}`, or `origin/<default branch>` when there is no upstream yet. Always pass it: on the default branch itself the plain "branch diff" is empty.

## Runtimes

Codex. `/codex:adversarial-review` is user-only (`disable-model-invocation`), so call the runtime directly. This picks this project's install first, then the user-scope one, so a pinned version is honoured:

    CODEX="$(jq -r --arg p "$(git rev-parse --show-toplevel)" '.plugins["codex@openai-codex"] | (map(select(.scope=="project" and .projectPath==$p)) + map(select(.scope=="user")))[0].installPath' ~/.claude/plugins/installed_plugins.json)/scripts/codex-companion.mjs"
    test -f "$CODEX" || echo "codex plugin not installed: $CODEX"

Codex is unavailable when that file is missing or the run reports no credits or an auth error.

DeepSeek. A script drives opencode's read-only `deepseek-reviewer` agent (it cannot edit, run commands or fetch URLs). The script lives two levels up from this skill's base directory. Bash timeout 600000 ms:

    bash "<base directory>/../../scripts/deepseek.sh" review "$(git rev-parse --show-toplevel)" <base> <<'REVIEW_END'
    <what changed and why, in two or three lines>
    REVIEW_END

Output starting with `DEEPSEEK_UNAVAILABLE` (exit 3) means unavailable.

## On a plan (before implementation)

1. Codex: `node "$CODEX" adversarial-review --wait "review the plan in <plan path>"`. If Codex is unavailable, run the DeepSeek script without `<base>`, with `review the plan in <plan path>` as the heredoc text.
2. Apply every finding you agree with to the plan. For each finding you reject, add one line under `## Review notes` in the plan saying why.

## On a diff (before push)

1. Commit everything (`git status` clean). The gate keys the marker to HEAD.
2. Pick the reviewer from the table and run it. Codex: `node "$CODEX" adversarial-review --wait --base <base> --scope branch`. DeepSeek: the script above.
3. Fix real findings, commit, and run the same reviewer again until it reports nothing material. Max 3 rounds; after that, list the remaining findings to the user and stop.
4. Record the marker for the final HEAD, naming the reviewer:

    d="$(git rev-parse --git-dir)/campanha"; mkdir -p "$d" && echo "<codex|deepseek>" > "$d/reviewed-$(git rev-parse HEAD)"

5. Invoke the `doc-keeper` agent in mode push (it writes the docs marker). Only then push.

Never write the marker without running the review. If the required reviewer and its fallback are both unavailable, tell the user and stop; do not push.
