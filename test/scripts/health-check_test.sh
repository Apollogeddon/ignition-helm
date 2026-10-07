#!/usr/bin/env bash
# Runs the chart's health-check.sh against a stub curl that returns canned
# /StatusPing and /system/gwinfo bodies. Usage: test/scripts/health-check_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" --show-only templates/configmap-scripts.yaml |
  awk '/^  health-check.sh: \|-/ {on=1; next} on && /^  [^ ]/ {on=0} on {sub(/^    /, ""); print}' > "$work/health-check.sh"
[ -s "$work/health-check.sh" ] || { echo "could not extract health-check.sh"; exit 1; }

mkdir "$work/bin"
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do url=$a; done
case "$url" in
  */StatusPing) [ -n "${PING:-}" ] || exit 7; printf '%s' "$PING" ;;
  */system/gwinfo) [ -n "${GWINFO:-}" ] || exit 7; printf '%s' "$GWINFO" ;;
esac
STUB
chmod +x "$work/bin/curl"

fails=0
# check <expected exit> <description> <env...> -- <args...>
check() {
  local want=$1 desc=$2; shift 2
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  env PATH="$work/bin:$PATH" "${envs[@]}" bash "$work/health-check.sh" "$@" > /dev/null
  local got=$?
  if [ "$got" -eq "$want" ]; then echo "ok   $desc"; else echo "FAIL $desc (exit $got, want $want)"; fails=$((fails + 1)); fi
}

check 0 "running passes" PING='{"state":"RUNNING"}' --
check 1 "not responding fails" PING= --
check 1 "starting fails" PING='{"state":"STARTING"}' --
check 0 "custom state" PING='{"state":"STARTING"}' -- -s STARTING
check 0 "liveness tolerates commissioning" PING='{"state":"RUNNING","details":"COMMISSIONING"}' --
check 1 "readiness fails while commissioning" PING='{"state":"RUNNING","details":"COMMISSIONING"}' -- -r
check 0 "readiness passes when running" PING='{"state":"RUNNING"}' -- -r

SYNC=IGNITION_READY_REQUIRES_BACKUP_SYNC=true
GOOD_BACKUP="ContextStatus=RUNNING;RedundancyStatus=Backup;RedundantState=Good;RedundantNodeActiveStatus=Cold;"
STALE_BACKUP="ContextStatus=RUNNING;RedundancyStatus=Backup;RedundantState=Unknown;RedundantNodeActiveStatus=Cold;"
MASTER="ContextStatus=RUNNING;RedundancyStatus=Master;RedundantState=Unknown;RedundantNodeActiveStatus=Active;"
check 0 "backup sync ignored unless required" PING='{"state":"RUNNING"}' GWINFO="$STALE_BACKUP" -- -r
check 0 "backup in sync is ready" PING='{"state":"RUNNING"}' GWINFO="$GOOD_BACKUP" "$SYNC" -- -r
check 1 "backup out of sync is not ready" PING='{"state":"RUNNING"}' GWINFO="$STALE_BACKUP" "$SYNC" -- -r
check 0 "master ready without a peer" PING='{"state":"RUNNING"}' GWINFO="$MASTER" "$SYNC" -- -r
check 1 "no gwinfo answer is not ready" PING='{"state":"RUNNING"}' GWINFO= "$SYNC" -- -r
check 0 "liveness ignores backup sync" PING='{"state":"RUNNING"}' GWINFO="$STALE_BACKUP" "$SYNC" --

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
