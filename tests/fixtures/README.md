# Manual smoke with Claude

    cd $(mktemp -d) && git init && npm init -y
    claude --plugin-dir ~/projects/campanha-dev-standards/plugins/core

Inside Claude:
1. `/adopt` → answer the project name and tenant. Expect the template rendered, lefthook installed, and a doc-keeper bootstrap report if the repo had docs.
2. Ask Claude to `git commit --no-verify` → expect the hook to deny.
3. Make a change, commit, `git push` → expect the pre-push `docs` or `review` step to block.
4. Run the doc-keeper agent (mode diff), fix findings, push again.
