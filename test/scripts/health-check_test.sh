#!/usr/bin/env bash
# Runs the chart's health-check.sh against a stub curl that returns canned
# /StatusPing and /system/gwinfo bodies. Usage: test/scripts/health-check_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" -f "$root/charts/failover/ci/deploy-values.yaml" --show-only templates/configmap-scripts.yaml |
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

# A Backup Incompatible with its Master (modules or version differ, as after a
# rolling update replaced the Backup first) is Ready for a limited time, so the
# StatefulSet goes on to the Master; Good clears the clock. Every change is
# logged once to HEALTH_CHECK_LOG.
INCOMPAT_BACKUP="ContextStatus=RUNNING;RedundancyStatus=Backup;RedundantState=Incompatible;RedundantNodeActiveStatus=Cold;"
INCOMPAT_MASTER="ContextStatus=RUNNING;RedundancyStatus=Master;RedundantState=Modules_Incompatible;RedundantNodeActiveStatus=Active;"
state="$work/state"; mkdir "$state"
# holds <description> <command...>: the command succeeds
holds() {
  if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
log_lines() { [ "$(wc -l < "$log")" -eq "$1" ]; }
clock_started_and_logged() { [ -s "$since" ] && grep -q "Incompatible with the Master" "$log" && log_lines 1; }
clock_cleared_and_logged() { [ ! -e "$since" ] && grep -q "in sync with the Master again" "$log"; }
since="$state/health-check.incompatible-since"
log="$work/gateway.log"
HC=(PING='{"state":"RUNNING"}' "$SYNC" HEALTH_CHECK_STATE_DIR="$state" HEALTH_CHECK_LOG="$log")
check 0 "incompatible backup is ready" "${HC[@]}" GWINFO="$INCOMPAT_BACKUP" -- -r
holds "incompatible start recorded and logged once" clock_started_and_logged
check 0 "incompatible backup stays ready within the limit" "${HC[@]}" GWINFO="$INCOMPAT_BACKUP" -- -r
holds "incompatible not logged again" log_lines 1
check 1 "unknown backup still not ready while incompatible clock runs" "${HC[@]}" GWINFO="$STALE_BACKUP" -- -r
holds "unknown keeps the incompatible clock" test -s "$since"
echo $(( $(date +%s) - 1801 )) > "$since"
check 1 "incompatible backup past the limit is not ready" "${HC[@]}" GWINFO="$INCOMPAT_BACKUP" -- -r
check 0 "limit is configurable" "${HC[@]}" GWINFO="$INCOMPAT_BACKUP" IGNITION_READY_INCOMPATIBLE_SECONDS=7200 -- -r
check 0 "good backup is ready again" "${HC[@]}" GWINFO="$GOOD_BACKUP" -- -r
holds "good clears the clock and logs it" clock_cleared_and_logged
check 0 "incompatible clock restarts after good" "${HC[@]}" GWINFO="$INCOMPAT_BACKUP" -- -r
check 0 "incompatible master is ready" "${HC[@]}" GWINFO="$INCOMPAT_MASTER" -- -r
rm -f "$since"
check 0 "incompatible ignored without backup sync" PING='{"state":"RUNNING"}' HEALTH_CHECK_STATE_DIR="$state" HEALTH_CHECK_LOG="$log" GWINFO="$INCOMPAT_BACKUP" -- -r
holds "no incompatible clock without backup sync" test ! -e "$since"
echo garbage > "$since"
check 0 "a corrupt clock starts again" "${HC[@]}" GWINFO="$INCOMPAT_BACKUP" -- -r
check 0 "unwritable log does not fail the probe" PING='{"state":"RUNNING"}' "$SYNC" HEALTH_CHECK_STATE_DIR="$work/new" HEALTH_CHECK_LOG=/nonexistent/x GWINFO="$INCOMPAT_BACKUP" -- -r
check 1 "other backup states are still not ready" "${HC[@]}" GWINFO="${STALE_BACKUP/Unknown/Faulted}" -- -r

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
