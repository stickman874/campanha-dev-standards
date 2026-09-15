// opencode plugin: runs the core PreToolUse/Bash hooks on opencode's bash tool, so
// opencode sessions (including `opencode run --auto` workers) hit the same gates as Claude.
// Rules live only in ../hooks/*.sh; this file just feeds them Claude's hook JSON.
// A hook that cannot run blocks the command (loud), unlike missing jq inside a hook (fails open by design).
// ponytail: guardrail, not a sandbox — it matches paths and command text, so a determined shell can still
// reach secrets (rg --hidden, python open, ...). That is why the unattended worker agent has no shell;
// a real sandbox (.env* unreadable at the filesystem level) is the upgrade path.
import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// realpath: the file is usually symlinked into ~/.config/opencode/plugins/
const HOOKS = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "..", "hooks");
const SCRIPTS = ["block-secrets.sh", "block-unsafe-bash.sh"];

// native file tools (read, edit, write, grep, glob, list) take filePath/path; same rule as the Claude settings deny list
const SECRET_FILE = /(^|\/)\.env(\.[^/]+)?$/;
const matchesSecret = (p) => SECRET_FILE.test(p) && !p.endsWith(".env.example");
// check the name as given and, if it exists, where it really points (config/current -> ../.env.production)
const isSecretFile = (p, dir) => {
  if (typeof p !== "string" || !p) return false;
  if (matchesSecret(p)) return true;
  try { return matchesSecret(realpathSync(isAbsolute(p) ? p : resolve(dir ?? process.cwd(), p))); } catch { return false; }
};
// apply_patch carries its targets inside patchText: Add/Delete/Update File and Move to
const patchTargets = (text) =>
  typeof text === "string" ? [...text.matchAll(/^\*\*\* (?:Add File|Delete File|Update File|Move to):\s*(.+)$/gm)].map((m) => m[1].trim()) : [];

// A broad grep (no include/path) still searches secret files; drop their matches from the result.
// Handles "path:" headers with indented "Line N:" rows and inline "path:N:text" rows.
const redactSecretMatches = (text, dir) => {
  let inSecret = false, redacted = 0;
  const kept = text.split("\n").filter((line) => {
    const header = /^(\S.*):$/.exec(line);
    if (header) { inSecret = isSecretFile(header[1].trim(), dir); if (inSecret) redacted++; return !inSecret; }
    const inline = /^([^\s:]+):\d+:/.exec(line);
    if (inline) { if (isSecretFile(inline[1], dir)) { redacted++; return false; } return true; }
    if (/^\s/.test(line)) return !inSecret;
    inSecret = false;
    return true;
  });
  return redacted ? kept.join("\n") + `\n[core guard: matches in ${redacted} secret file(s) redacted]` : text;
};

export const CoreGuard = async ({ directory } = {}) => ({
  "tool.execute.after": async (input, output) => {
    if (input.tool === "grep" && typeof output.output === "string") output.output = redactSecretMatches(output.output, directory);
  },
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") {
      // grep/glob `include` globs (".env*", "*.env.local") would return secret-file contents from a directory search
      const include = output.args?.include;
      const secretInclude = typeof include === "string" && /\.env/.test(include.replace(/\.env\.example/g, ""));
      const targets = [output.args?.filePath, output.args?.path, ...patchTargets(output.args?.patchText)];
      if (secretInclude || targets.some((p) => isSecretFile(p, directory)))
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
