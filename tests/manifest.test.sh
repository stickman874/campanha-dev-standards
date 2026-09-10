#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
m=.claude-plugin/marketplace.json; p=plugins/core/.claude-plugin/plugin.json
assert_eq campanha-dev-standards "$(jq -r .name $m)" "marketplace name"
assert_eq ./plugins/core "$(jq -r '.plugins[0].source' $m)" "plugin source path"
assert_eq core "$(jq -r .name $p)" "plugin name"
assert_eq ./hooks/hooks.json "$(jq -r .hooks $p)" "plugin hooks pointer"
finish
