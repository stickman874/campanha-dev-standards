# Manual smoke with Claude

    cd $(mktemp -d) && git init && npm init -y
    claude --plugin-dir ~/projects/campanha-dev-standards/plugins/core

Inside Claude:
1. `/adopt` → answer "single". Expect templates created and a bootstrap report.
2. Ask Claude to `cat .env` → expect the hook to deny.
3. Make a change, commit, `git push` → expect the pre-push `docs` or `review` step to block.
4. Run the doc-keeper agent (mode diff), fix findings, push again.
