#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
assert_exit 0 bash -n install.sh
assert_contains "$(bash install.sh --check 2>&1)" 'lefthook' "check mode lists tools"
assert_contains "$(head -4 plugins/core/commands/docs-consolidate.md)" 'description:' "command frontmatter"
finish
