#!/usr/bin/env bash
# Dry-runs .github/scripts/e2e/run-scenarios.sh for every scenario script, every
# shortcut in its case statement and the E2E workflow's default list: each must
# resolve to a script and pass only VAR=value arguments.
# Usage: test/scripts/run-scenarios_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1
runner=.github/scripts/e2e/run-scenarios.sh

scripts=$(ls test/e2e/s[0-9]*-*.sh | xargs -n1 basename | sed 's/\.sh$//')
shortcuts=$(grep -oE '^ +s[0-9]+-[a-z-]+(:[a-z]+)?\)' "$runner" | tr -d ' )')
defaults=$(grep -oE "inputs.scenarios \|\| '[^']*'" .github/workflows/e2e.yaml | sed "s/.*|| '//; s/'$//")
all=$(printf '%s\n' $scripts $shortcuts $defaults | sort -u | paste -sd' ' -)

out=$(E2E_DRY_RUN=true NODE_IP=0.0.0.0 INGRESS_PORT=0 E2E_OUT="$(mktemp -d)" SCENARIOS="$all" bash "$runner" 2>&1)
echo "$out" | grep -E '^(PASS|FAIL) '
fails=$(echo "$out" | grep -c '^FAIL ' || true)
[ "$(echo "$out" | grep -c '^PASS ')" -gt 0 ] || { echo "nothing ran"; exit 1; }
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
