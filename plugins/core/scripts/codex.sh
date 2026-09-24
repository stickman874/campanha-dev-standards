#!/usr/bin/env bash
# plugins/core/scripts/codex.sh
# Codex backend of opencode.sh (same contract): runs one project agent unattended through `codex exec`.
#   codex.sh <repo> <agent> < prompt
# The agent's instructions are the body of .claude/agents/<agent>.md (its frontmatter model is ignored); the model is CODEX_MODEL.
# Env: CODEX_MODEL (gpt-6-sol), OPENCODE_TIMEOUT (seconds, 600), OPENCODE_EVENTS (save the raw JSONL events here).
# stdout: the agent's final text. stderr: "codex: tools=N tokens=T".
# Exit 0 done · 3 "CODEX_UNAVAILABLE: <why>" (codex/agent missing, login, rate limit, error event, timeout, crash) · 2 bad usage.
# Sandbox: reviewer read-only, anything else workspace-write; no network, no MCP (user config ignored).
# Codex has no dotenv deny rule: the reviewer runs in a throwaway worktree at HEAD, which has no untracked .env files
# (it could still read ../<repo>/.env by absolute path; the prompt forbids it).
# windows.sandbox=unelevated: the default Windows sandbox blocks even file reads; ignored on Linux.
set -u
repo=${1:-}; agent=${2:-}
[ -n "$agent" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "usage: codex.sh <repo> <agent> < prompt" >&2; exit 2; }
tmp=$(mktemp -d); pid=
SETSID=$(command -v setsid || true)
stop() {
  [ -n "$pid" ] || return 0
  if [ -n "$SETSID" ]; then kill -- "-$pid" 2>/dev/null; else kill "$pid" 2>/dev/null; fi
  for i in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if [ -n "$SETSID" ]; then kill -9 -- "-$pid" 2>/dev/null; else kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null; pid=
}
wt=
trap 'stop; [ -n "$wt" ] && git -C "$repo" worktree remove --force "$wt" 2>/dev/null; rm -rf "$tmp"' EXIT
cat > "$tmp/task"; [ -s "$tmp/task" ] || { echo "empty prompt" >&2; exit 2; }
events=${OPENCODE_EVENTS:-$tmp/events}; : > "$events"
text() { [ -s "$tmp/last" ] && { cat "$tmp/last"; return; }; jq -r 'select(.type=="item.completed" and .item.type=="agent_message") | .item.text' "$events" 2>/dev/null; }
unavailable() { stop; echo "CODEX_UNAVAILABLE: $1"; text; exit 3; }
command -v codex >/dev/null || unavailable "codex not installed (npm i -g @openai/codex; codex login), or not on PATH"
def="$repo/.claude/agents/$agent.md"
[ -f "$def" ] || unavailable ".claude/agents/$agent.md missing in the project (run copier update)"
{ awk 'f>=2; /^---$/{f++}' "$def"; echo; echo "# Task"; echo; cat "$tmp/task"; } > "$tmp/prompt"   # body after the frontmatter, then the task
cwd=$repo
case $agent in reviewer) sandbox=read-only
  git -C "$repo" worktree add -q --detach "$tmp/wt" HEAD 2>/dev/null && { wt=$tmp/wt; cwd=$wt; } || unavailable "cannot create a clean worktree at HEAD";;
  *) sandbox=workspace-write;; esac
last="$tmp/last"; command -v cygpath >/dev/null && last=$(cygpath -w "$last")   # Git Bash: codex.exe needs a Windows path
timeout=${OPENCODE_TIMEOUT:-600}; end=$(( $(date +%s) + timeout ))
(cd "$cwd" && exec ${SETSID:-} codex exec --json --ephemeral --ignore-user-config -m "${CODEX_MODEL:-gpt-6-sol}" -s "$sandbox" -c 'windows.sandbox="unelevated"' -o "$last" - < "$tmp/prompt") > "$events" 2> "$tmp/err" &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  [ "$(date +%s)" -ge "$end" ] && unavailable "timeout after ${timeout}s"
  sleep 1
done
wait "$pid"; code=$?; pid=
err=$(jq -r 'select(.type=="turn.failed" or .type=="error") | (.error.message // .message) | tostring' "$events" 2>/dev/null | head -1)
[ -n "$err" ] && unavailable "codex error: ${err:0:200}"
[ "$code" -eq 0 ] || unavailable "codex exited $code: $(grep -v '^[[:space:]]*$' "$tmp/err" | tail -1 | cut -c1-200)"
text
echo "codex: tools=$(jq -c 'select(.type=="item.completed" and .item.type!="agent_message" and .item.type!="reasoning")' "$events" 2>/dev/null | wc -l) tokens=$(jq -s '[.[] | select(.type=="turn.completed") | .usage.input_tokens + .usage.output_tokens] | add // 0' "$events")" >&2
