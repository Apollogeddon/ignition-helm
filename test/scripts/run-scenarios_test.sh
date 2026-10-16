#!/usr/bin/env bash
# Dry-runs .github/scripts/e2e/run-scenarios.sh for every scenario script, every
# shortcut in its case statement and the e2e workflow's default lists: each must
# resolve to a script and pass only VAR=value arguments.
# Usage: test/scripts/run-scenarios_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1
runner=.github/scripts/e2e/run-scenarios.sh

scripts=$(for f in test/e2e/s[0-9]*-*.sh; do basename "$f" .sh; done)
shortcuts=$(grep -oE '^ +s[0-9]+-[a-z-]+(:[a-z]+)?\)' "$runner" | tr -d ' )')
# the charts pipeline's default, and the one the e2e workflow's form offers
defaults=$(grep -oE "inputs.scenarios \|\| '[^']*'" .github/workflows/charts.yml | sed "s/.*|| '//; s/'$//")
defaults="$defaults $(sed -n 's/^ *default: *\(s[0-9].*\)$/\1/p' .github/workflows/.e2e.yml)"
[ -n "${defaults// /}" ] || { echo "no default scenarios found"; exit 1; }
all=$(printf '%s\n' "$scripts" "$shortcuts" "$defaults" | tr ' ' '\n' | grep -v '^$' | sort -u | paste -sd' ' -)

out=$(E2E_DRY_RUN=true NODE_IP=0.0.0.0 INGRESS_PORT=0 E2E_OUT="$(mktemp -d)" SCENARIOS="$all" bash "$runner" 2>&1)
echo "$out" | grep -E '^(PASS|FAIL) '
fails=$(echo "$out" | grep -c '^FAIL ' || true)
[ "$(echo "$out" | grep -c '^PASS ')" -gt 0 ] || { echo "nothing ran"; exit 1; }
if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
