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

# chart templates as the chart renders them (Master on pod 0, Backup on pod 1)
mkdir -p "$work/files"
template() { # template <role> <peer host> <recovery mode>
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<properties>' \
    "<entry key=\"redundancy.noderole\">$1</entry>" \
    '<entry key="redundancy.gan.pingRate">1000</entry>' \
    "<entry key=\"redundancy.gan.host\">$2</entry>" \
    '<entry key="redundancy.gan.port">8060</entry>' \
    "<entry key=\"redundancy.masterrecoverymode\">$3</entry>" \
    '<entry key="redundancy.systemstaterevision">0</entry>' \
    '<entry key="redundancy.systemstateuid">00000000-0000-0000-0000-000000000000</entry>' \
    '</properties>'
}
template Master ignition-failover-1.ignition-failover-headless Automatic > "$work/files/redundancy-primary.xml"
template Backup ignition-failover-0.ignition-failover-headless Automatic > "$work/files/redundancy-backup.xml"

fails=0
# fresh: start with an empty data dir; volume <role> <host> <mode>: a data dir holding a redundancy.xml
fresh() { rm -rf "$work/data"; mkdir "$work/data"; }
volume() {
  fresh
  template "$@" | sed -e 's|>0</entry>|>42</entry>|' \
    -e 's|00000000-0000-0000-0000-000000000000|1b2c3d4e-0000-0000-0000-000000000001|' \
    -e 's|</properties>|<entry key="redundancy.custom">keep-me</entry>\n</properties>|' > "$work/data/redundancy.xml"
}
# run <hostname> <replicas>
run() { HOSTNAME=$1 IGNITION_REPLICAS=$2 DATA_DIR="$work/data" FILES_DIR="$work/files" bash "$work/seed.sh" > "$work/out" 2>&1; }
get() { grep -F "key=\"$1\"" "$work/data/redundancy.xml" | sed 's/.*">\(.*\)<\/entry>.*/\1/'; }
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; sed 's/^/     /' "$work/out"; fails=$((fails + 1)); fi; }

fresh; run ignition-failover-0 2
ok "first start seeds the Master from the primary template" 'cmp -s "$work/data/redundancy.xml" "$work/files/redundancy-primary.xml"'
fresh; run ignition-failover-1 2
ok "first start seeds the Backup from the backup template" '[ "$(get redundancy.noderole)" = Backup ]'

volume Independent "" Automatic; run ignition-failover-0 2
ok "Independent becomes Master when redundancy is turned on" '[ "$(get redundancy.noderole)" = Master ]'
ok "the Master gets the peer host" '[ "$(get redundancy.gan.host)" = ignition-failover-1.ignition-failover-headless ]'
ok "Ignition sync state is kept" '[ "$(get redundancy.systemstaterevision)" = 42 ] && [ "$(get redundancy.systemstateuid)" = 1b2c3d4e-0000-0000-0000-000000000001 ]'
ok "keys the chart does not render are kept" '[ "$(get redundancy.custom)" = keep-me ]'

volume Independent "" Automatic; run ignition-failover-1 2
ok "Independent becomes Backup on pod 1" '[ "$(get redundancy.noderole)" = Backup ]'

volume Backup ignition-failover-1.ignition-failover-headless Automatic; run ignition-failover-0 2
ok "a wrong role on pod 0 is corrected to Master" '[ "$(get redundancy.noderole)" = Master ]'

volume Backup ignition-failover-0.ignition-failover Automatic; run ignition-failover-1 2
ok "a peer host from an older chart is corrected" '[ "$(get redundancy.gan.host)" = ignition-failover-0.ignition-failover-headless ]'
ok "the correction is logged" 'grep -q "Updating redundancy.gan.host: ignition-failover-0.ignition-failover -> " "$work/out"'

volume Backup ignition-failover-0.ignition-failover-headless Manual; run ignition-failover-1 2
ok "a changed value (master recovery mode) is applied" '[ "$(get redundancy.masterrecoverymode)" = Automatic ]'

volume Master ignition-failover-1.ignition-failover-headless Automatic
sed -i '/redundancy.gan.pingRate/d' "$work/data/redundancy.xml"; run ignition-failover-0 2
ok "a key missing from the volume is added" '[ "$(get redundancy.gan.pingRate)" = 1000 ]'
ok "the file still ends with </properties>" '[ "$(tail -1 "$work/data/redundancy.xml")" = "</properties>" ]'

volume Master ignition-failover-1.ignition-failover-headless Automatic; run ignition-failover-0 2
ok "a file that already matches is left alone" '! grep -q Updating "$work/out"'

volume Master ignition-failover-1.ignition-failover-headless Automatic; run ignition-failover-0 1
ok "turning redundancy off makes the gateway Independent" '[ "$(get redundancy.noderole)" = Independent ]'
ok "turning redundancy off keeps the other settings" '[ "$(get redundancy.gan.host)" = ignition-failover-1.ignition-failover-headless ]'

fresh; run ignition-failover-0 1
ok "a gateway that was never redundant gets no redundancy.xml" '[ ! -e "$work/data/redundancy.xml" ]'

printf '%s\r\n' '<properties>' '<entry key="redundancy.noderole">Master</entry>' '</properties>' > "$work/files/redundancy-primary.xml"
volume Master "" Automatic; printf '%s\n' '<properties>' '<entry key="redundancy.noderole">Master</entry>' '</properties>' > "$work/data/redundancy.xml"
run ignition-failover-0 2
ok "carriage returns in the template are not treated as changes" '! grep -q Updating "$work/out"'

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
