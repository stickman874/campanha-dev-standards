#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
G="$PWD/plugins/core/opencode/guard.js"
# run <guard-path> <tool> <command> [dir] → "allow" or "deny: <reason>"
# non-bash tools get the 3rd arg as filePath
run() { node --input-type=module -e '
  const [g, tool, value, directory] = process.argv.slice(1);
  const h = (await (await import(g)).CoreGuard({ directory }))["tool.execute.before"];
  const args = tool === "bash" ? { command: value } : { filePath: value, path: value };
  try { await h({ tool }, { args }); console.log("allow"); } catch (e) { console.log("deny: " + e.message); }
' "$@"; }

fake_gh="ghp_$(printf 'a%.0s' $(seq 1 36))"
assert_contains "$(run "$G" bash "echo $fake_gh")" '^deny' "secret denied"
assert_contains "$(run "$G" bash 'git commit -m x --no-verify')" 'Never bypass' "--no-verify denied with hook reason"
assert_contains "$(run "$G" bash 'cat .env')" '^deny' ".env denied"
assert_contains "$(run "$G" bash 'cat deploy/.env.secrets')" '^deny' "qualified .env path denied"
assert_contains "$(run "$G" bash 'cat /srv/app/.env')" '^deny' "absolute .env path denied"
assert_eq allow "$(run "$G" bash 'cat deploy/.env.example')" "qualified .env.example allowed"
assert_eq allow "$(run "$G" bash 'git status')" "safe command allowed"
assert_contains "$(run "$G" read /app/.env)" '^deny' "native read of .env denied"
assert_contains "$(run "$G" read apps/web/.env.local)" '^deny' "native read of .env.local denied"
assert_contains "$(run "$G" grep /app/.env.production)" '^deny' "grep on .env.production denied"
assert_eq allow "$(run "$G" read /app/.env.example)" "native read of .env.example allowed"
inc() { node --input-type=module -e '
  const [g, include] = process.argv.slice(1);
  const h = (await (await import(g)).CoreGuard({}))["tool.execute.before"];
  try { await h({ tool: "grep" }, { args: { pattern: ".", path: "/app", include } }); console.log("allow"); } catch (e) { console.log("deny: " + e.message); }
' "$@"; }
assert_contains "$(inc "$G" '.env*')" '^deny' "grep include .env* denied"
assert_contains "$(inc "$G" '*.env.local')" '^deny' "grep include *.env.local denied"
assert_eq allow "$(inc "$G" '.env.example')" "grep include .env.example allowed"
assert_eq allow "$(inc "$G" '*.{ts,tsx}')" "grep include source globs allowed"
after() { node --input-type=module -e '
  const [g, text] = process.argv.slice(1);
  const out = { output: text };
  await (await import(g)).CoreGuard({}).then((h) => h["tool.execute.after"]({ tool: "grep" }, out));
  console.log(out.output);
' "$@"; }
canary="SECRET_VALUE_X"
blocks=$(after "$G" "$(printf 'Found 2 matches\n/app/.env:\n  Line 1: K=%s\n\n/app/src/a.ts:\n  Line 3: const k = 1\n' "$canary")")
assert_eq 0 "$(printf '%s' "$blocks" | grep -c "$canary")" "broad grep: secret-file block redacted"
assert_contains "$blocks" 'Line 3: const k' "broad grep: other files kept"
assert_contains "$blocks" 'redacted' "broad grep: redaction noted"
inline=$(after "$G" "$(printf 'deploy/.env.secrets:2:K=%s\nsrc/a.ts:3:const k\n' "$canary")")
assert_eq 0 "$(printf '%s' "$inline" | grep -c "$canary")" "inline grep rows from secret files redacted"
assert_contains "$(after "$G" "$(printf '/app/.env.example:\n  Line 1: K=\n')")" 'Line 1: K=' ".env.example matches kept"
assert_eq allow "$(run "$G" read src/env.ts)" "native read of ordinary file allowed"

D=$(mktemp -d); mkdir -p "$D/config"; : > "$D/.env.production"; ln -s ../.env.production "$D/config/current"; printf 'x\n' > "$D/ok.ts"
assert_contains "$(run "$G" read config/current "$D")" '^deny' "symlink to a secret file denied"
assert_eq allow "$(run "$G" read ok.ts "$D")" "ordinary file next to it allowed"
rm -rf "$D"
ap() { node --input-type=module -e '
  const [g, patchText] = process.argv.slice(1);
  const h = (await (await import(g)).CoreGuard({}))["tool.execute.before"];
  try { await h({ tool: "apply_patch" }, { args: { patchText } }); console.log("allow"); } catch (e) { console.log("deny: " + e.message); }
' "$@"; }
assert_contains "$(ap "$G" "$(printf '*** Begin Patch\n*** Delete File: /app/.env\n*** End Patch')")" '^deny' "apply_patch delete of .env denied"
assert_contains "$(ap "$G" "$(printf '*** Begin Patch\n*** Update File: src/a.ts\n*** Move to: deploy/.env.secrets\n@@\n-a\n+b\n*** End Patch')")" '^deny' "apply_patch move onto .env denied"
assert_contains "$(ap "$G" "$(printf '*** Begin Patch\n*** Add File: .env.local\n+K=v\n*** End Patch')")" '^deny' "apply_patch add .env.local denied"
assert_eq allow "$(ap "$G" "$(printf '*** Begin Patch\n*** Update File: src/a.ts\n@@\n-a\n+b\n*** End Patch')")" "apply_patch on source allowed"

T=$(mktemp -d); git -C "$T" init -q; git -C "$T" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
assert_contains "$(run "$G" bash 'git push origin main' "$T")" 'codex-review' "push without review markers denied"

# symlinked install still finds ../hooks; a copy without hooks blocks loudly
ln -s "$G" "$T/linked.js"; cp "$G" "$T/orphan.js"
assert_contains "$(run "$T/linked.js" bash 'cat .env')" '^deny' "works through symlink"
assert_contains "$(run "$T/orphan.js" bash 'git status')" 'could not run' "missing hooks block"
rm -rf "$T"
finish
