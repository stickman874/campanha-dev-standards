// opencode plugin: runs the core PreToolUse/Bash hooks on opencode's bash tool, so
// opencode sessions (including `opencode run --auto` workers) hit the same gates as Claude.
// Rules live only in ../hooks/*.sh; this file just feeds them Claude's hook JSON.
// A hook that cannot run blocks the command (loud), unlike missing jq inside a hook (fails open by design).
import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// realpath: the file is usually symlinked into ~/.config/opencode/plugins/
const HOOKS = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "..", "hooks");
const SCRIPTS = ["block-secrets.sh", "block-unsafe-bash.sh", "pre-push-gate.sh"];

export const CoreGuard = async ({ directory } = {}) => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") return;
    const stdin = JSON.stringify({ tool_name: "Bash", tool_input: { command: output.args?.command ?? "" } });
    for (const s of SCRIPTS) {
      const r = spawnSync("bash", [join(HOOKS, s)], { input: stdin, encoding: "utf8", cwd: output.args?.workdir ?? directory });
      if (r.error || r.status !== 0) throw new Error(`core guard: ${s} could not run (${r.error?.message ?? r.stderr.trim()}); command blocked.`);
      if (!r.stdout.trim()) continue;
      let d;
      try { d = JSON.parse(r.stdout).hookSpecificOutput; } catch { throw new Error(`core guard: ${s} returned unreadable output; command blocked.`); }
      if (d?.permissionDecision === "deny") throw new Error(d.permissionDecisionReason);
    }
  },
});
