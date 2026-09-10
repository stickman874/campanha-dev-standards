# Manual smoke with Claude

    cd $(mktemp -d) && git init && npm init -y
    claude --plugin-dir ~/projects/campanha-dev-standards/plugins/core

Inside Claude:
1. `/adopt` → answer "single". Expect templates created and a bootstrap report.
2. Ask Claude to `cat .env` → expect the hook to deny.
3. Make a change, commit, ask Claude to `git push` → expect denial naming `codex-review`.
4. Run the `codex-review` skill, then `doc-keeper` mode push, then push → expect lefthook pre-push to run.
