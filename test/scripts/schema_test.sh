#!/usr/bin/env bash
# Checks the charts' values.schema.json: every values file the repository ships
# (charts/*/ci, examples/, test/e2e/values) validates, and a misspelt key, at
# the top level, in a gateway's values or nested below them, fails the render
# instead of being ignored.
# Usage: test/scripts/schema_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fails=0
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# valid <chart> <values file>: renders, so the schema accepts it
valid() {
  if "$HELM" template t "$root/charts/$1" -f "$2" > /dev/null 2> "$work/err"; then
    echo "ok   ${2#"$root"/} validates"
  else
    fail "${2#"$root"/} does not validate against the $1 schema"; sed 's/^/     /' "$work/err"
  fi
}

# refused <chart> <key=value> <misspelt key>: the schema rejects it, naming it
refused() {
  local key=${2%%=*}
  if "$HELM" template t "$root/charts/$1" -f "$root/charts/$1/ci/deploy-values.yaml" --set "$2" > /dev/null 2> "$work/err"; then
    fail "$1 renders with the misspelt $key"
  elif grep -q "additional properties '$3' not allowed" "$work/err"; then
    echo "ok   $1 refuses $key"
  else
    fail "$1 refuses $key, but not as an unknown key:"; sed 's/^/     /' "$work/err"
  fi
}

for f in "$root"/charts/failover/ci/*.yaml "$root"/test/e2e/values/small.yaml; do valid failover "$f"; done
for f in "$root"/charts/scaleout/ci/*.yaml "$root"/test/e2e/values/small-scaleout.yaml; do valid scaleout "$f"; done
while IFS= read -r f; do
  case "$f" in */examples/scaleout/*) valid scaleout "$f" ;; *) valid failover "$f" ;; esac
done < <(find "$root/examples" -name '*.yaml' | sort)

refused failover acceptEULA=true acceptEULA
refused failover ignition.redundency.enabled=true redundency
refused failover ignition.service.prots.http=80 prots
refused failover ignition.startupProbe.failureTreshold=90 failureTreshold
refused failover ignition.existingSecrets=x existingSecrets
refused scaleout acceptEULA=true acceptEULA
refused scaleout frontend.hpa.minReplica=2 minReplica
refused scaleout backend.redundency.enabled=true redundency
refused scaleout backend.activeRouting.enable=true enable
refused scaleout frontend.existingSecrets=x existingSecrets

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
