#!/usr/bin/env bash
# Runs the chart's seed-redundancy.sh against a temporary data directory.
# Usage: test/scripts/seed-redundancy_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" --show-only templates/configmap-scripts.yaml |
  awk '/^  seed-redundancy.sh: \|-/ {on=1; next} on && /^  [^ ]/ {on=0} on {sub(/^    /, ""); print}' > "$work/seed.sh"
[ -s "$work/seed.sh" ] || { echo "could not extract seed-redundancy.sh"; exit 1; }

mkdir -p "$work/files"
entry() { printf '  <entry key="%s">%s</entry>\n' "$1" "$2"; }
{ echo '<properties>'; entry redundancy.mode Master; entry redundancy.gan.host ignition-failover-1.ignition-failover-headless
  entry redundancy.gan.port 8060; entry redundancy.masterrecoverymode Automatic; echo '</properties>'; } > "$work/files/redundancy-primary.xml"
{ echo '<properties>'; entry redundancy.mode Backup; entry redundancy.gan.host ignition-failover-0.ignition-failover-headless
  entry redundancy.gan.port 8060; entry redundancy.masterrecoverymode Automatic; echo '</properties>'; } > "$work/files/redundancy-backup.xml"

fails=0
# run <hostname> <replicas>: run seed.sh with a fresh data dir prepared by the caller in $work/data
run() { HOSTNAME=$1 IGNITION_REPLICAS=$2 DATA_DIR="$work/data" FILES_DIR="$work/files" bash "$work/seed.sh" > "$work/out" 2>&1; }
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; cat "$work/out"; fails=$((fails + 1)); fi; }
host() { grep 'redundancy.gan.host' "$work/data/redundancy.xml" | sed 's/.*">\(.*\)<.*/\1/'; }

rm -rf "$work/data"; mkdir "$work/data"; run ignition-failover-0 2
ok "first start seeds the Master from the primary template" 'cmp -s "$work/data/redundancy.xml" "$work/files/redundancy-primary.xml"'

rm -rf "$work/data"; mkdir "$work/data"
sed -e 's/ignition-failover-0.ignition-failover-headless/ignition-failover-0.ignition-failover/' \
  -e 's/>Automatic</>Manual</' "$work/files/redundancy-backup.xml" > "$work/data/redundancy.xml"
run ignition-failover-1 2
ok "a peer host from an older chart is corrected" '[ "$(host)" = ignition-failover-0.ignition-failover-headless ]'
ok "other settings on the volume are kept" 'grep -q ">Manual<" "$work/data/redundancy.xml"'
ok "the correction is logged" 'grep -q "Updating redundancy.gan.host" "$work/out"'

run ignition-failover-1 2
ok "a correct file is left alone" '! grep -q Updating "$work/out"'

rm -rf "$work/data"; mkdir "$work/data"; run ignition-failover-0 1
ok "a single replica writes nothing" '[ ! -e "$work/data/redundancy.xml" ]'

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
