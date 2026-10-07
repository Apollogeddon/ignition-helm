#!/usr/bin/env bash
# S03: redundancy values take effect on an existing install. For each Ignition
# version: install standalone, turn redundancy on, change a redundancy value,
# turn redundancy off, and turn it back on (the Backup's volume is kept). Each
# step checks the gateways' roles from /system/gwinfo and their redundancy.xml,
# and records how long the NodePort was not served by an Active gateway.
#
# Env: NODE_IP, IMAGE_TAGS (default "8.1.53 8.3.1"), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
: "${NODE_IP:?}"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover
IMAGE_TAGS="${IMAGE_TAGS:-8.1.53 8.3.1}"

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s03)
out="$E2E_OUT/s03-summary.txt"
failed=""

# role <pod>: RedundancyStatus/RedundantState/RedundantNodeActiveStatus from
# gwinfo, or just "Independent" for a gateway without redundancy (which
# reports Independent/Good/Active, or no fields); "down" if it does not answer
role() {
  local info
  info=$(kubectl -n "$ns" exec "$1" -c gateway -- curl -s --max-time 3 http://localhost:8088/system/gwinfo 2>/dev/null || true)
  [ -n "$info" ] || { echo down; return; }
  info=$(tr ';' '\n' <<< "$info" | grep -E '^(RedundancyStatus|RedundantState|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -)
  case "${info}" in ""|Independent/*) echo Independent ;; *) echo "${info}" ;; esac
}
# setting <pod> <key>: a value from the pod's redundancy.xml
setting() {
  kubectl -n "$ns" exec "$1" -c gateway -- sh -c "grep -F 'key=\"redundancy.$2\"' /usr/local/bin/ignition/data/redundancy.xml" 2>/dev/null |
    sed 's/.*">\(.*\)<\/entry>.*/\1/' | tr -d '\r'
}
uid() { kubectl -n "$ns" get pod "$1" -o jsonpath='{.metadata.uid}' 2>/dev/null || true; }
# wait_rollout <replicas>: StatefulSet settled at that many Ready replicas
wait_rollout() {
  local want=$1 deadline=$(( $(date +%s) + 900 )) cur upd ready total
  while [ "$(date +%s)" -lt "$deadline" ]; do
    read -r cur upd ready total <<< "$(kubectl -n "$ns" get sts $STS       -o jsonpath='{.status.currentRevision} {.status.updateRevision} {.status.readyReplicas} {.status.replicas}' || true)"
    [ -n "$cur" ] && [ "$cur" = "$upd" ] && [ "${ready:-0}" = "$want" ] && [ "${total:-0}" = "$want" ] && return 0
    sleep 5
  done
  e2e_diagnose "$ns"
  die "StatefulSet did not settle at $1 Ready replicas"
}
# wait_roles <expected pod-0 role> [<expected pod-1 role>]: poll gwinfo until both match
wait_roles() {
  local deadline=$(( $(date +%s) + 900 )) r0 r1
  while [ "$(date +%s)" -lt "$deadline" ]; do
    r0=$(role $STS-0); r1=${2:+$(role $STS-1)}
    [ "$r0" = "$1" ] && [ "${r1}" = "${2:-}" ] && return 0
    sleep 5
  done
  log "roles: $STS-0=$r0${2:+, $STS-1=$r1}"
  return 1
}
# step <name> <helm --set args...>: upgrade, recording availability until the caller's checks finish
rec=""
start_recording() {
  local np
  np=$(kubectl -n "$ns" get svc $STS -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
  "$(dirname "$0")/record.sh" 1200 "$E2E_OUT/s03-$tag-$1.log" via="http://$NODE_IP:$np/system/gwinfo" &
  rec=$!
}
stop_recording() {
  kill "$rec" 2>/dev/null; wait "$rec" 2>/dev/null || true
  awk '{split($2, v, "="); if (v[2] ~ /\/Active$|^Independent$/) run = 0; else {run++; if (run > max) max = run}}
    END {printf "%d", max + 0}' "$E2E_OUT/s03-$tag-$1.log"
}
check() { # check <tag> <step> <description> <test...>
  local t=$1 s=$2 d=$3; shift 3
  if "$@"; then echo "  $t $s: ok   $d" | tee -a "$out" >&2
  else echo "  $t $s: FAIL $d" | tee -a "$out" >&2; failed="$failed $t:$s"; fi
}
init_log() { kubectl -n "$ns" logs "$1" -c preconfigure 2>/dev/null | grep -E 'Updating redundancy|Initializing Redundancy|no redundancy settings' | tr '\n' ' '; }

for tag in $IMAGE_TAGS; do
  e2e_require_memory "$ns"
  base=(s03 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml" --set "image.tag=$tag" --set ignition.service.type=NodePort)
  e2e_render_check "${base[@]}"
  echo "S03 $(date -u +%FT%TZ) image=$tag" >> "$out"

  log "$tag 1/5: standalone"
  e2e_install "${base[@]}"
  e2e_wait_ready "$ns" 900
  check "$tag" 1 "standalone reports Independent ($(role $STS-0))" [ "$(role $STS-0)" = Independent ]
  r=$(setting $STS-0 noderole)
  check "$tag" 1 "redundancy.xml absent or Independent (${r:-absent})" [ "${r:-Independent}" = Independent ]

  log "$tag 2/5: redundancy on"
  u0=$(uid $STS-0); start_recording on
  e2e_install "${base[@]}" --set ignition.redundancy.enabled=true
  wait_rollout 2
  wait_roles Master/Good/Active Backup/Good/Cold || true
  gap=$(stop_recording on)
  check "$tag" 2 "pod 0 restarted" [ "$(uid $STS-0)" != "$u0" ]
  check "$tag" 2 "pair formed ($(role $STS-0), $(role $STS-1))" wait_roles Master/Good/Active Backup/Good/Cold
  check "$tag" 2 "longest unserved ${gap}s; pod 0 init: $(init_log $STS-0)" true

  log "$tag 3/5: change a redundancy value (masterRecoveryMode=Manual)"
  u0=$(uid $STS-0); u1=$(uid $STS-1); start_recording value
  e2e_install "${base[@]}" --set ignition.redundancy.enabled=true --set ignition.redundancy.masterRecoveryMode=Manual
  wait_rollout 2
  wait_roles Master/Good/Active Backup/Good/Cold || true
  gap=$(stop_recording value)
  check "$tag" 3 "both pods restarted" [ "$(uid $STS-0)" != "$u0" -a "$(uid $STS-1)" != "$u1" ]
  check "$tag" 3 "both redundancy.xml say Manual" [ "$(setting $STS-0 masterrecoverymode)/$(setting $STS-1 masterrecoverymode)" = Manual/Manual ]
  check "$tag" 3 "pair healthy ($(role $STS-0), $(role $STS-1)); longest unserved ${gap}s" wait_roles Master/Good/Active Backup/Good/Cold

  log "$tag 4/5: redundancy off"
  u0=$(uid $STS-0); start_recording off
  e2e_install "${base[@]}"
  wait_rollout 1
  wait_roles Independent || true
  gap=$(stop_recording off)
  check "$tag" 4 "pod 1 removed" [ -z "$(uid $STS-1)" ]
  check "$tag" 4 "pod 0 restarted" [ "$(uid $STS-0)" != "$u0" ]
  check "$tag" 4 "pod 0 reports Independent ($(role $STS-0)); longest unserved ${gap}s" wait_roles Independent
  check "$tag" 4 "pod 0 redundancy.xml says Independent; init: $(init_log $STS-0)" [ "$(setting $STS-0 noderole)" = Independent ]
  sleep 60
  check "$tag" 4 "still Independent a minute later" wait_roles Independent

  log "$tag 5/5: redundancy back on (Backup volume kept)"
  start_recording again
  e2e_install "${base[@]}" --set ignition.redundancy.enabled=true
  wait_rollout 2
  wait_roles Master/Good/Active Backup/Good/Cold || true
  gap=$(stop_recording again)
  check "$tag" 5 "pair formed again ($(role $STS-0), $(role $STS-1)); longest unserved ${gap}s" wait_roles Master/Good/Active Backup/Good/Cold

  e2e_watch_check
  e2e_retry "$HELM" uninstall s03 -n "$ns" --wait >/dev/null || true
  kubectl -n "$ns" delete pvc --all --wait=true >/dev/null
done

[ -z "$failed" ] || die "S03:$failed"
log "S03 passed"
