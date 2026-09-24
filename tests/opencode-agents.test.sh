#!/usr/bin/env bash
# tests/opencode-agents.test.sh — opencode agent modes and models, and the orchestrator's bash guard (mirror of the Claude hooks)
source "$(dirname "$0")/lib.sh"
A=template/.opencode/agents
fm() { sed -n '2,/^---$/p' "$A/$1.md" 2>/dev/null; }
for a in orchestrator worker rescuer reviewer docs; do
  [ -f "$A/$a.md" ] && echo "  ok  $a.md exists" || { echo "  FAIL $a.md missing"; FAILS=$((FAILS+1)); }
  cmp -s "$A/$a.md" ".opencode/agents/$a.md" && echo "  ok  root copy of $a.md in sync" || { echo "  FAIL root .opencode/agents/$a.md differs"; FAILS=$((FAILS+1)); }
done
assert_contains "$(fm orchestrator)" '^mode: primary$' "orchestrator is primary"
assert_contains "$(fm orchestrator)" '^model: openai/gpt-6-sol$' "orchestrator on gpt-6-sol"
assert_contains "$(fm orchestrator)" '^reasoningEffort: medium$' "orchestrator effort medium"
assert_contains "$(fm rescuer)" '^model: openai/gpt-6-sol$' "rescuer on gpt-6-sol"
assert_contains "$(fm rescuer)" '^reasoningEffort: high$' "rescuer effort high"
assert_contains "$(fm rescuer)" '^  bash: deny$' "rescuer has no shell"
for a in worker rescuer reviewer docs; do assert_contains "$(fm $a)" '^mode: all$' "$a usable as subagent and by opencode run"; done
for a in worker reviewer docs; do assert_contains "$(fm $a)" '^model: opencode-go/deepseek-v4.1-flash$' "$a on DeepSeek"; done
assert_eq orchestrator "$(jq -r .default_agent template/opencode.json)" "plain opencode start lands on the orchestrator"

command -v opencode >/dev/null || { echo "  skip live checks (no opencode)"; finish; }
W=$(mktemp -d); mkdir -p "$W/.opencode/agents" "$W/bin"; cp "$A"/*.md "$W/.opencode/agents/"; cp template/opencode.json "$W/"
git -C "$W" init -q; printf 'SECRET=fake\n' > "$W/.env"; printf 'SECRET=\n' > "$W/.env.example"
# `opencode debug agent --tool bash` really executes an allowed command, so every external tool a case names is a stub:
# a broken guard runs a stub, never git/cat/npx for real, and an allowed case must print the stub's marker.
for t in git cat less head grep npx supabase prisma env python node; do printf '#!/usr/bin/env bash\necho "STUB-%s $*"\n' "$t" > "$W/bin/$t"; chmod +x "$W/bin/$t"; done
# Scoped (not exported) so only the opencode subshells see the stubs; this shell's own grep (assert_contains, denied)
# must keep using the real one — this bash has no command hash cache, so a global export would shadow itself too.
STUBPATH="$W/bin:$PATH"
assert_eq orchestrator "$(cd "$W" && PATH="$STUBPATH" timeout 60 opencode debug config 2>/dev/null | jq -r .default_agent)" "resolved default_agent"
assert_eq medium "$(cd "$W" && PATH="$STUBPATH" timeout 60 opencode debug agent orchestrator 2>/dev/null | jq -r .options.reasoningEffort)" "reasoningEffort in the agent's provider options"
call() { (cd "$W" && PATH="$STUBPATH" timeout 60 opencode debug agent orchestrator --tool bash --params "$(jq -nc --arg c "$1" '{command:$c,description:"t"}')" 2>&1); }
denied() { out=$(call "$1"); assert_contains "$out" 'prevents you from using this specific tool call' "orchestrator denies: $1"
  printf '%s' "$out" | grep -q 'STUB-' && { echo "  FAIL denied command still ran: $1"; FAILS=$((FAILS+1)); } || true; }
allowed() { out=$(call "$1"); assert_contains "$out" "$2" "orchestrator runs: $1"; }   # a positive marker, so a timeout or parse error is a FAIL
t20() { printf "$1%.0s" $(seq 1 "$2"); }   # token shapes are built at runtime so none lives in the repo
# known gap (opencode 1.18.31): bare assignments/exports ("export VAR=…", "VAR=…" alone) are never checked against permission.bash, so no pattern can deny them; inline prefixes ("VAR=1 git push", "env VAR=1 …") are denied. The night shift reviews every pushed range.
for c in 'cat .env' 'cd app && cat .env.local' 'source .env.production' 'cat deploy/.env.secrets' 'export $(cat .env | xargs)' \
  'cat "deploy/.env.secrets"' "cat '.env.local'" 'cat .env.local .env.example' 'cat .env.example' 'grep KEY .env .env.example' \
  'git commit -m x --no-verify' 'git push --no-verify' 'cd app && git push origin main --no-verify' \
  'git -c core.hooksPath=/dev/null push' 'git config core.hooksPath /dev/null' 'LEFTHOOK=0 git push' 'LEFTHOOK_EXCLUDE=review git push' \
  'SKIP_REVIEW=1 git push' 'env SKIP_REVIEW=1 git push' 'OPENCODE_SH=./x.sh git push' 'command git push --no-verify' 'if true; then git push --no-verify; fi' \
  'npx prisma db push' 'npx prisma migrate reset' 'supabase db reset --linked' \
  "echo ghp_$(t20 a 36)" "echo github_pat_$(t20 a 30)" "echo sk-proj-$(t20 a 20)" "echo sk-ant-$(t20 a 20)" "echo sk_live_$(t20 a 20)" "echo rk_live_$(t20 a 20)" \
  "echo xoxb-$(t20 1 10)" "echo xoxa-$(t20 1 10)" "echo xoxp-$(t20 1 10)" "echo xoxr-$(t20 1 10)" "echo xoxs-$(t20 1 10)" \
  "echo AKIA$(t20 A 16)" "echo ASIA$(t20 A 16)" "echo AIza$(t20 a 35)" "echo glpat-$(t20 a 20)" "echo sb_secret_$(t20 a 8)" \
  "echo eyJ$(t20 a 8).eyJ$(t20 a 8).x" 'echo https://hooks.slack.com/services/T0/B0/x' "echo '-----BEGIN RSA PRIVATE KEY-----'"; do denied "$c"; done
allowed 'git status' 'STUB-git status'
allowed 'git push origin main' 'STUB-git push origin main'
allowed 'npx prisma migrate dev --name add_x' 'STUB-npx prisma migrate dev'
allowed 'supabase db reset' 'STUB-supabase db reset'
allowed 'git worktree add .opencode/worktrees/task-login -b task-login' 'STUB-git worktree add'
rm -rf "$W"; finish
