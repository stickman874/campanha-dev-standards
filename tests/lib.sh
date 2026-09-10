#!/usr/bin/env bash
FAILS=0
assert_eq() { [ "$1" = "$2" ] && echo "  ok  $3" || { echo "  FAIL $3: expected [$1] got [$2]"; FAILS=$((FAILS+1)); }; }
assert_contains() { printf '%s' "$1" | grep -q -- "$2" && echo "  ok  $3" || { echo "  FAIL $3: [$2] not in output"; FAILS=$((FAILS+1)); }; }
assert_exit() { local want=$1; shift; "$@" >/dev/null 2>&1; local got=$?; assert_eq "$want" "$got" "exit code of: $*"; }
finish() { [ $FAILS -eq 0 ] && exit 0 || exit 1; }
