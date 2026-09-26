# Design system

Source of truth for visual decisions; every screen uses only what is listed here.

## Tokens

| Token | Purpose | Value lives in |
| --- | --- | --- |
| `--brand` | Primary brand colour | `globals.css` |
| `--radius` | Corner rounding | `globals.css` |

## Type scale

| Name | Size | Use for |
| --- | --- | --- |
| `text-sm` | 14px | Body text |
| `text-lg` | 18px | Section headings |

## Canonical components

| Component | Use for | File |
| --- | --- | --- |
| `Button` | All clickable actions | `components/ui/button.tsx` |
| `Card` | Grouped content blocks | `components/ui/card.tsx` |

## Rules

- No inline colours or sizes; use tokens and canonical components only.
- Missing a piece? shadcn (Base UI) first, then ReUI (MCP + `reui` skill), then your own shared component — in that order. Register it here, never inline.
- Run impeccable to regenerate this file after design changes (enable `impeccable@impeccable` in `.claude/settings.json` first; it is off by default).
