# How to add a UI component

Order of preference. Stop at the first rung that fits; never hand-roll what a
registry already ships.

1. **shadcn standard (Base UI).** `npx shadcn@latest search <term>`; install
   with `bash scripts/ui-add.sh <name>` (stamps the header the ui-primitives
   lint requires). Buttons, dialogs, selects, inputs, cards, sheets live here.
2. **ReUI** — only when shadcn has nothing that satisfies the need (data grid
   with sorting/filtering/CRUD, kanban, column filters, date range, tree,
   stepper, full-page blocks). Use the MCP + `reui` skill, never the docs site:
   - `search(intent)` → pick 1–3 results (each carries `install`, `previewUrl`,
     `componentsUsed`); show the preview link to the owner.
   - `get_component([...componentsUsed])` in one batched call → read the inline
     API. `validate_usage` before writing props you have not read.
   - `get_examples(component)` → install one `c-*` example, copy its composition.
   - Install: `bash scripts/ui-add.sh @reui/<name>`.
   - Adapt by reuse: real data, project tokens from `globals.css`, no invented
     props, no restyling. `get_audit_checklist()` before declaring done.
   - Free account covers components + examples. Premium blocks need a Pro
     licence: ask the owner before installing one.
3. **Your own shared component**, in the shared components folder, registered
   in `DESIGN.md`. Never a one-off inside a screen.

## Setup (once per machine)

```bash
REUI_GLOBAL=1 curl -fsSL https://mcp.reui.io/install | node -
```

Writes the `reui` skill to `~/.claude/skills/reui` and `~/.agents/skills/reui`,
the MCP to `~/.claude.json` (Claude Code) and `~/.codex/config.toml` (Codex).
For opencode add by hand: copy the skill to `~/.config/opencode/skills/reui` and
in `~/.config/opencode/opencode.jsonc`:

```jsonc
"mcp": { "reui": { "type": "remote", "url": "https://mcp.reui.io/api/mcp", "enabled": true } }
```

First use opens "Sign in with ReUI" in the browser (free account). Headless/CI:
personal token from https://reui.io/account/mcp as `Authorization: Bearer`.
