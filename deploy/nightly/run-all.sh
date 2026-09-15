#!/usr/bin/env bash
# Runs nightly.sh for every checkout listed in /etc/campanha/repos (one absolute path per line; file is server-local, never committed).
set -u
list=${1:-/etc/campanha/repos}; here=$(cd "$(dirname "$0")" && pwd); rc=0
while read -r repo; do [ -n "$repo" ] && [ "${repo#\#}" = "$repo" ] || continue; bash "$here/../../plugins/core/scripts/nightly.sh" "$repo" || rc=1; done < "$list"
exit $rc
