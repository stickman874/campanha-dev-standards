#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
G="$PWD/plugins/core/opencode/guard.js"
# run <guard-path> <tool> <command> [dir] → "allow" or "deny: <reason>"
run() { node --input-type=module -e '
  const [g, tool, command, directory] = process.argv.slice(1);
  const h = (await (await import(g)).CoreGuard({ directory }))["tool.execute.before"];
  try { await h({ tool }, { args: { command } }); console.log("allow"); } catch (e) { console.log("deny: " + e.message); }
' "$@"; }

fake_gh="ghp_$(printf 'a%.0s' $(seq 1 36))"
assert_contains "$(run "$G" bash "echo $fake_gh")" '^deny' "secret denied"
assert_contains "$(run "$G" bash 'git commit -m x --no-verify')" 'Never bypass' "--no-verify denied with hook reason"
assert_contains "$(run "$G" bash 'cat .env')" '^deny' ".env denied"
assert_eq allow "$(run "$G" bash 'git status')" "safe command allowed"
assert_eq allow "$(run "$G" read 'cat .env')" "non-bash tools ignored"

T=$(mktemp -d); git -C "$T" init -q; git -C "$T" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
assert_contains "$(run "$G" bash 'git push origin main' "$T")" 'codex-review' "push without review markers denied"

# symlinked install still finds ../hooks; a copy without hooks blocks loudly
ln -s "$G" "$T/linked.js"; cp "$G" "$T/orphan.js"
assert_contains "$(run "$T/linked.js" bash 'cat .env')" '^deny' "works through symlink"
assert_contains "$(run "$T/orphan.js" bash 'git status')" 'could not run' "missing hooks block"
rm -rf "$T"
finish
