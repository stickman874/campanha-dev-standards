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

// native file tools (read, edit, write, grep, glob, list) take filePath/path; same rule as the Claude settings deny list
const SECRET_FILE = /(^|\/)\.env(\.[^/]+)?$/;
const isSecretFile = (p) => typeof p === "string" && SECRET_FILE.test(p) && !p.endsWith(".env.example");

// A broad grep (no include/path) still searches secret files; drop their matches from the result.
// Handles "path:" headers with indented "Line N:" rows and inline "path:N:text" rows.
const redactSecretMatches = (text) => {
  let inSecret = false, redacted = 0;
  const kept = text.split("\n").filter((line) => {
    const header = /^(\S.*):$/.exec(line);
    if (header) { inSecret = isSecretFile(header[1].trim()); if (inSecret) redacted++; return !inSecret; }
    const inline = /^([^\s:]+):\d+:/.exec(line);
    if (inline) { if (isSecretFile(inline[1])) { redacted++; return false; } return true; }
    if (/^\s/.test(line)) return !inSecret;
    inSecret = false;
    return true;
  });
  return redacted ? kept.join("\n") + `\n[core guard: matches in ${redacted} secret file(s) redacted]` : text;
};

export const CoreGuard = async ({ directory } = {}) => ({
  "tool.execute.after": async (input, output) => {
    if (input.tool === "grep" && typeof output.output === "string") output.output = redactSecretMatches(output.output);
  },
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") {
      // grep/glob `include` globs (".env*", "*.env.local") would return secret-file contents from a directory search
      const include = output.args?.include;
      const secretInclude = typeof include === "string" && /\.env/.test(include.replace(/\.env\.example/g, ""));
      if (secretInclude || [output.args?.filePath, output.args?.path].some(isSecretFile))
        throw new Error("Reading .env files is blocked: secrets must never enter the transcript. Use .env.example to see variable names.");
      return;
    }
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
