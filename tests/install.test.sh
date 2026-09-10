#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
assert_exit 0 bash -n install.sh
assert_contains "$(bash install.sh --check 2>&1)" 'lefthook' "check mode lists tools"
assert_contains "$(head -4 plugins/core/commands/docs-consolidate.md)" 'description:' "command frontmatter"
assert_contains "$(cat install.sh)" 'uv tool install semgrep' "uv path for semgrep"
assert_contains "$(cat install.sh)" 'exit 1' "fail loudly on missing tools"
finish
