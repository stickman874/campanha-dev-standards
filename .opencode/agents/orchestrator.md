---
description: Orchestrator for this repository. Plans, delegates to the worker/rescuer/reviewer/docs subagents, verifies, runs tests and git, commits.
mode: primary
model: openai/gpt-6-sol
reasoningEffort: medium
permission:
  # Mirror of the Claude hooks (block-unsafe-bash.sh, block-secrets.sh), which do not run in opencode.
  # Each command is split into its parts and every part is checked; the last matching rule wins.
  read:
    "*": allow
    "*.env": deny
    "*.env.*": deny
    "*.env.example": allow
  bash:
    "*": allow
    "*git *--no-verify*": deny
    "*git *--no-gpg-sign*": deny
    "*git *core.hooksPath*": deny
    "*lefthook*--no-verify*": deny
    "*SKIP_REVIEW=*": deny
    "*LEFTHOOK=0*": deny
    "*LEFTHOOK_EXCLUDE=*": deny
    "*OPENCODE_SH=*": deny
    "*prisma db push*": deny
    "*prisma migrate reset*": deny
    "*supabase db reset*--linked*": deny
    "*git commit* -n*": deny
    "*git commit* -an*": deny
    "*git *--no-ve*": deny
    "*git *ooks?ath*": deny
    "*git *OOKS?ATH*": deny
    "*git *push*prod*": deny
    "*git *push*--force*": deny
    "*git *push* -f*": deny
    "*git *push* +*": deny
    "*tac *.env*": deny
    "*sort *.env*": deny
    "*uniq *.env*": deny
    "*strings *.env*": deny
    "*od *.env*": deny
    "*xxd *.env*": deny
    "*base64 *.env*": deny
    "*nl *.env*": deny
    "*find *.env*": deny
    "*cat *.env*": deny
    "*less *.env*": deny
    "*more *.env*": deny
    "*head *.env*": deny
    "*tail *.env*": deny
    "*bat *.env*": deny
    "*source *.env*": deny
    ". *.env*": deny
    "*grep *.env*": deny
    "*rg *.env*": deny
    "*sed *.env*": deny
    "*awk *.env*": deny
    "*cut *.env*": deny
    "*cp *.env*": deny
    "*mv *.env*": deny
    "*python* *.env*": deny
    "*node *.env*": deny
    "*eyJ*.eyJ*": deny
    "*sb_secret_*": deny
    "*AKIA*": deny
    "*ASIA*": deny
    "*ghp_*": deny
    "*gho_*": deny
    "*ghu_*": deny
    "*ghs_*": deny
    "*ghr_*": deny
    "*github_pat_*": deny
    # plain "sk-<20+ chars>" has no wildcard form that spares "task-..." branch names; the named prefixes are covered
    "*sk-proj-*": deny
    "*sk-ant-*": deny
    "*sk_live_*": deny
    "*rk_live_*": deny
    "*xoxa-*": deny
    "*xoxb-*": deny
    "*xoxp-*": deny
    "*xoxr-*": deny
    "*xoxs-*": deny
    "*AIza*": deny
    "*glpat-*": deny
    "*hooks.slack.com/services/*": deny
    "*PRIVATE KEY-----*": deny
    # no .env.example carve-outs: wildcards match the whole command, so "cat .env.local .env.example" would slip through.
    # Read .env.example with the read tool instead.
    # Known gap: opencode does not check bare "export VAR=…" commands, so "export SKIP_REVIEW=1; git push" is not denied here; the night shift reviews every pushed range.
---

You are the orchestrator for this repository. `AGENTS.md` is your rulebook; its `## opencode` section tells you how to brief, run in parallel and verify subagents.

- You plan, decide, delegate, verify and commit. Subagents never commit.
- Scoped edits and code searches → `worker`. Stuck after two attempts → `rescuer`. Spec and plan review → `reviewer`. Docs → `docs`.
- Parallelise as much as possible (see `AGENTS.md`).
- You run the tests and git yourself. Never read `.env` files; read `.env.example` with the read tool, not the shell. Never bypass the git hooks; your bash permission blocks it. When the push review blocks, fix the `[high]` findings or tell the user the exact command they can type themselves.
