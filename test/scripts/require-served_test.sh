#!/usr/bin/env bash
# Checks e2e_require_served (test/e2e/lib.sh): a scenario stops when a recorded
# path was never served, so a blocked path can't pass as an outage.
# Usage: test/scripts/require-served_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fails=0
# check <description> <want exit 0|1> <log lines> [target...]
check() {
  local desc=$1 want=$2 status=0; printf '%s\n' "$3" > "$work/rec.log"; shift 3
  ( E2E_OUT="$work/out"; source "$root/test/e2e/lib.sh"; e2e_require_served "$work/rec.log" "$@" ) \
    > /dev/null 2>&1 || status=1
  if [ "$status" = "$want" ]; then echo "ok   $desc"; else echo "FAIL $desc (exit $status)"; fails=$((fails + 1)); fi
}

check "every target served at least once passes" 0 $'10:00:00 ingress=000 via=down\n10:00:01 ingress=200 via=Master/Good/Active'
check "a target never served stops the scenario" 1 $'10:00:00 ingress=000 nodeport=200\n10:00:01 ingress=000 nodeport=200'
check "a cold Backup or an error page is not served" 1 $'10:00:00 via=Backup/Good/Cold\n10:00:01 via=error:503'
check "a standalone gateway is served" 0 '10:00:00 via=Independent'
check "only the named targets are required" 0 $'10:00:00 ingress=000 nodeport=200' nodeport
check "a named target missing from the log stops it" 1 '10:00:00 nodeport=200' ingress
check "an empty log stops it" 1 ''
status=0
( E2E_OUT="$work/out"; source "$root/test/e2e/lib.sh"; e2e_require_served "$work/none.log" ) > /dev/null 2>&1 || status=1
if [ "$status" = 1 ]; then echo "ok   a missing log stops it"; else echo "FAIL a missing log stops it"; fails=$((fails + 1)); fi

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
