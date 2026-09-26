# 2026-09-26: Claude Code slowness and the slim-down

Status: **done (0.5.5, uncommitted).** See "Decisions after re-measure" at the end.

## Problem

Claude Code felt sluggish after adopting campanha-dev-standards. Question was whether to go back to
"vanilla" (Opus + superpowers + ponytail + LSP + good instructions).

## Findings

1. **The machine: every Git Bash program start takes ~3-5 s** (PowerShell starts the same exe in ~0.03 s).
   Every hook, status-line refresh and Bash tool call pays it.
   - Not the MSYS account lookup: `nsswitch.conf` set to `passwd: files` / `group: files` and
     `/etc/passwd` + `/etc/group` generated (admin; backup `C:\Program Files\Git\etc\nsswitch.conf.bak`). No change. Left in place (harmless).
   - Killed 3 orphan runaways: an opencode test `sh` (`grep KEY .env ...`, 31 h CPU since 24/09) and two `find / -iname reviewer-rubric.md` (~4 h CPU each).
   - Still open: ~81 leftover bash processes; two VS Code `tsserver` for `manage` at >1 core each. Suspects left: leftovers (reboot) → Windows Defender real-time scanning of Git (`C:\Program Files\Git`, `~\projects` exclusion, admin).
2. **Hooks multiply that cost.** `core`'s two PreToolUse/Bash hooks took 49-76 s per Bash command in isolation
   (each spawns `jq` + many `grep`). `security-guidance` (enabled by the template) runs 11 hooks. `npx -y ccstatusline@latest` status line took 42 s.
3. **Benchmark** (`bench-settings.ps1`, same 3×`echo` task, headless, sonnet, one run each, slow machine):

   | Config | Wall | Startup context | Total input |
   |---|---|---|---|
   | Template settings today | 355 s | 46.3k | 233k |
   | Same, no sandbox | 383 s | 46.3k | 233k |
   | Slim (superpowers, codex, typescript-lsp) | 155 s | 44.9k | 225k |

   - Slim is ~2.3× faster. The template's extra plugins cost only ~1.5k tokens; the other ~45k is the
     global setup (system prompt, skill lists, MCP connectors, CLAUDE.md).
   - Sandbox: no measurable cost → keep it.
   - Slim still 155 s for 3 echoes (should be ~15 s) → the machine problem above.

## Conclusions (keep)

- Don't go vanilla; **slim the template's `.claude/settings.json`**. Project settings override global ones,
  so every adopted repo (e.g. `manage`) re-enables everything.
- Keep, per the original goals:
  - Development: superpowers + Codex adversarial review of specs/plans (already in `template/CLAUDE.md`, via `codex:codex-rescue`; `/codex:adversarial-review` also exists). Codex plugin stays; its hooks are cheap once process starts are fast, and its session hook cleans up broker processes. Never enable its stop review gate.
  - Security: lefthook gates (gitleaks, eslint, tsc, vitest related, `review.sh`) + `permissions.deny` + sandbox.
  - Docs: `doc-keeper`, night shift, `/adopt`, `/docs-consolidate`.
- Drop from the template: `core` plugin (its two Bash hooks → `permissions.deny` rules), `security-guidance`,
  `impeccable` (turn on per project for UI work), `commit-commands`, `playwright` (uninstalled globally 2026-09-26; the Playwright CLI is the path).
- Next token lever is the global MCP connectors, not the standards.
- Lesson: self-made commands/scripts/hooks is how this got bloated. Prefer what official plugins already ship.

## Done already (outside this repo)

- `~/.claude/settings.json`: status line → `node .../ccstatusline/dist/ccstatusline.js` (installed globally; 0.27 s);
  plugins off: `core`, `impeccable`, `feature-dev` (codex back on); 29 `permissions.deny` rules replacing `core`'s hooks + `find /`.
- `/adopt`, `/docs-consolidate`, `doc-keeper` copied to `~/.claude/commands` and `~/.claude/agents` (text only).
- `~/.agents/AGENTS.md` trimmed 6.5 KB → ~2 KB; Hetzner details moved to `~/.agents/infra-hetzner.md`;
  added "never search the whole disk". `~/.claude/CLAUDE.md` worker rule to one line.
- Open question for the owner: `mechanical tasks → Haiku` memory vs "Haiku only after Haiku 5.5" (template `CLAUDE.md`).

## Next steps

1. Reboot. Then time a Git Bash start: `Measure-Command { & "C:\Program Files\Git\bin\bash.exe" -c "/usr/bin/true" }` (goal: < 0.2 s) and rerun `bench-settings.ps1`.
2. Still slow → Defender exclusion for `C:\Program Files\Git` and `~\projects` (admin), re-measure.
3. Make the template change (settings, README "What you get", CHANGELOG, version bump), roll out with `copier update --trust` + hand-edit each adopted repo's `.claude/settings.json` (copier never overwrites `.claude/`).
4. Uninstall `core` and `feature-dev` globally.

## After reboot (2026-09-26)

- Git Bash start from PowerShell: **0.04 s** (5 runs, 0.038-0.072 s; was ~3-5 s). Goal < 0.2 s met.
  Cause was the leftover processes; the reboot cleared them. Defender exclusion not needed, not done.
- Leftover bash/sh processes: 3 (this session's own; was ~81).
- `bench-settings.ps1` rerun (same task, one run each). "Template" now = template minus `playwright` (uncommitted edit):

  | Config | Wall before | Wall after | Startup context | Total input |
  |---|---|---|---|---|
  | Template settings | 355 s | 16.2 s | 45.6k | 229k |
  | Same, no sandbox | 383 s | 14.8 s | 44.5k | 228k |
  | Slim | 155 s | 14.3 s | 44.8k | 225k |

- Reading: the machine was ~95% of the slowness. With fast process starts the full template costs only
  ~2 s (~13%) and ~4k tokens more than slim on this task. Slim-down is still worth it (fewer hooks per
  Bash call, less to maintain), but it is no longer urgent.

## Decisions after re-measure (2026-09-26)

- **`core` stays** (template and global), hooks included: on a healthy machine they are cheap, they catch more
  bypass tricks than glob deny rules, and `core` is how teammates get `doc-keeper`, `/adopt`, `/docs-consolidate`.
  The `~/.claude` copies of those were moved to `~/.claude/skills/.trash/`. This replaces next steps 3-4 above.
- Template 0.5.5 enables core, superpowers, typescript-lsp, codex. Dropped security-guidance, commit-commands,
  playwright, impeccable. Hand-edited `.claude/settings.json` in the 10 repos under `~/projects` that had them (uncommitted there).
- Global: `feature-dev` uninstalled; `playwright` project installs removed in `manage` and `splitnice`;
  old `grilling` skill copy (one question at a time) moved to `.trash` (mattpocock's current one stays).
- claude.ai connectors off in the CLI (`env.ENABLE_CLAUDEAI_MCP_SERVERS=false` in `~/.claude/settings.json`):
  startup context 45.1k → 42.4k tokens; also removes the manage-between "always answer in Portuguese" and
  Claude Docs "make a doc first" instructions from coding sessions. They still work on claude.ai.
- Template `AGENTS.md`: the `## opencode` worker contract moved to `.opencode/agents/orchestrator.md` (~1.8 KB less per Claude session).
  Adopted repos pick it up with `copier update --trust` + deleting their `## opencode` section by hand.
- Memories: deleted `mechanical-tasks-use-haiku` (contradicted "workers on Sonnet"); rewrote `dev-standards-slim-down`
  and `campanha-dev-standards` (was 2026-09-11 state); removed 9 benchmark memory folders.
- Not touched: `collie` (third-party repo, 54 KB `CLAUDE.md`), the skill packs (owner keeps all three), global
  `AGENTS.md`/`CLAUDE.md` overlap with the template (a few hundred bytes; needed for non-adopted repos).
