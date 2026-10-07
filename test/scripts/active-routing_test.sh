#!/usr/bin/env bash
# Runs one poll of the chart's active-routing.sh against stub kubectl and curl
# and checks which pods it labels or unlabels.
# Usage: test/scripts/active-routing_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" --show-only templates/configmap-scripts.yaml |
  awk '/^  active-routing.sh: \|-/ {on=1; next} on && /^  [^ ]/ {on=0} on {sub(/^    /, ""); print}' > "$work/active-routing.sh"
[ -s "$work/active-routing.sh" ] || { echo "could not extract active-routing.sh"; exit 1; }

mkdir "$work/bin"
# kubectl: "get pods" prints $PODS (name|ip|deletionTimestamp|label lines);
# "label pod <name> ... <label>=true|<label>-" is recorded in $CALLS
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "get pods") printf '%s\n' "$PODS" ;;
  "label pod") echo "$3 ${!#}" >> "$CALLS" ;;
esac
STUB
# curl: answers http://<ip>:8088/system/gwinfo from $GW_<ip with dots as _>
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do url=$a; done
ip=${url#http://}; ip=${ip%%:*}; var="GW_${ip//./_}"
[ -n "${!var:-}" ] || exit 7
printf '%s' "${!var}"
STUB
chmod +x "$work/bin/"*

MASTER="ContextStatus=RUNNING;RedundancyStatus=Master;RedundantState=Good;RedundantNodeActiveStatus=Active;"
MASTER_COLD="ContextStatus=RUNNING;RedundancyStatus=Master;RedundantState=Good;RedundantNodeActiveStatus=Cold;"
BACKUP_COLD="ContextStatus=RUNNING;RedundancyStatus=Backup;RedundantState=Good;RedundantNodeActiveStatus=Cold;"
BACKUP_ACTIVE="ContextStatus=RUNNING;RedundancyStatus=Backup;RedundantState=Unknown;RedundantNodeActiveStatus=Active;"
STANDALONE="ContextStatus=RUNNING;"
COMMISSIONING="ContextStatus=NEEDS_COMMISSIONING;"

fails=0
# check <description> <expected label changes, e.g. "gw-0 +|gw-1 -" or ""> <env...>
check() {
  local desc=$1 want=$2; shift 2
  : > "$work/calls"
  env PATH="$work/bin:$PATH" CALLS="$work/calls" NAMESPACE=ns POD_SELECTOR=app=gw ACTIVE_LABEL=redundancy-active \
    MAX_LOOPS=1 "$@" sh "$work/active-routing.sh" > /dev/null
  local got
  got=$(sed -e 's/ redundancy-active-$/ -/' -e 's/ --overwrite$/ +/' "$work/calls" | sort | paste -sd'|' -)
  if [ "$got" = "$want" ]; then echo "ok   $desc"; else echo "FAIL $desc (got '$got', want '$want')"; fails=$((fails + 1)); fi
}

check "labels the active Master" "gw-0 +" \
  PODS=$'gw-0|10.0.0.1||\ngw-1|10.0.0.2||' GW_10_0_0_1="$MASTER" GW_10_0_0_2="$BACKUP_COLD"
check "leaves a correct label alone" "" \
  PODS=$'gw-0|10.0.0.1||true\ngw-1|10.0.0.2||' GW_10_0_0_1="$MASTER" GW_10_0_0_2="$BACKUP_COLD"
check "moves to a Backup that took over" "gw-0 -|gw-1 +" \
  PODS=$'gw-0|10.0.0.1||true\ngw-1|10.0.0.2||' GW_10_0_0_1="$MASTER_COLD" GW_10_0_0_2="$BACKUP_ACTIVE"
check "prefers the Master when both report Active" "gw-0 +|gw-1 -" \
  PODS=$'gw-0|10.0.0.1||\ngw-1|10.0.0.2||true' GW_10_0_0_1="$MASTER" GW_10_0_0_2="$BACKUP_ACTIVE"
check "prefers the Master whatever the listing order" "gw-0 +|gw-1 -" \
  PODS=$'gw-1|10.0.0.2||true\ngw-0|10.0.0.1||' GW_10_0_0_1="$MASTER" GW_10_0_0_2="$BACKUP_ACTIVE"
check "holds the label through one unanswered poll" "" \
  PODS=$'gw-0|10.0.0.1||true\ngw-1|10.0.0.2||' GW_10_0_0_2="$BACKUP_COLD"
check "unlabels a terminating pod" "gw-0 -|gw-1 +" \
  PODS=$'gw-0|10.0.0.1|2026-01-01T00:00:00Z|true\ngw-1|10.0.0.2||' GW_10_0_0_1="$MASTER" GW_10_0_0_2="$BACKUP_ACTIVE"
check "labels a standalone gateway" "gw-0 +" \
  PODS=$'gw-0|10.0.0.1||' GW_10_0_0_1="$STANDALONE"
check "does not label a gateway that is commissioning" "" \
  PODS=$'gw-0|10.0.0.1||' GW_10_0_0_1="$COMMISSIONING"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
