#!/usr/bin/env bash
# S10: network faults on a redundant pair with activeRouting (needs Chaos Mesh,
# so run it on a disposable cluster, not a shared one).
#   A. split-brain: partition the Master from the Backup only. The Backup takes
#      over while the Master keeps running, so both report Active; the labeller
#      must keep traffic on one gateway, and the pair must settle after the
#      partition heals.
#   B. hung Master: isolate the Master from everything. Measures how long user
#      traffic is not served until the Backup takes over.
# Each second the labelled pod and both gateways' states are recorded.
#
# Env: NODE_IP, IMAGE_TAG (default chart appVersion), PARTITION_SECONDS (default 90)
source "$(dirname "$0")/lib.sh"
: "${NODE_IP:?}"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover
PARTITION_SECONDS="${PARTITION_SECONDS:-90}"

kubectl get crd networkchaos.chaos-mesh.org >/dev/null 2>&1 || die "S10 needs Chaos Mesh (NetworkChaos CRD not found)"

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s10)
e2e_require_memory "$ns"

args=(s10 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml"
  --set ignition.redundancy.enabled=true
  --set ignition.activeRouting.enabled=true)
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")
e2e_render_check "${args[@]}"
log "installing redundant pair with activeRouting"
e2e_install "${args[@]}"
e2e_wait_ready "$ns" 900

gwinfo() { kubectl -n "$ns" exec "$1" -c gateway -- curl -s --max-time 2 http://localhost:8088/system/gwinfo 2>/dev/null |
  tr ';' '\n' | grep -E '^(RedundancyStatus|RedundantState|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -; }
wait_pair() {
  local deadline=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    [ "$(gwinfo $STS-0 || true)" = Master/Good/Active ] && [ "$(gwinfo $STS-1 || true)" = Backup/Good/Cold ] && return 0
    sleep 5
  done
  return 1
}
wait_pair 600 || die "pair not healthy before the test"

# state recorder: time, labelled pods, each gateway's role/state/active
states() {
  local end=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    echo "$(date -u +%H:%M:%S) labelled=$(kubectl -n "$ns" get pods -l redundancy-active=true -o name 2>/dev/null | sed 's|pod/||' | paste -sd, -) 0=$(gwinfo $STS-0 || echo down) 1=$(gwinfo $STS-1 || echo down)"
    sleep 1
  done >> "$2"
}
nodeport=$(kubectl -n "$ns" get svc $STS-active -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

# fault <name> <spec yaml>: apply a NetworkChaos for PARTITION_SECONDS and record around it
fault() {
  local name=$1 spec=$2 window=$(( PARTITION_SECONDS + 240 ))
  log "$name: recording ${window}s"
  "$(dirname "$0")/record.sh" "$window" "$E2E_OUT/s10-$name-traffic.log" via="http://$NODE_IP:$nodeport/system/gwinfo" &
  local rec=$!
  states "$window" "$E2E_OUT/s10-$name-states.log" &
  local st=$!
  sleep 10
  log "$name: injecting for ${PARTITION_SECONDS}s"
  kubectl -n "$ns" apply -f - >/dev/null <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: s10-$name
spec:
  mode: all
  duration: ${PARTITION_SECONDS}s
$spec
EOF
  wait "$rec" "$st" 2>/dev/null || true
  kubectl -n "$ns" delete networkchaos "s10-$name" --wait=true >/dev/null || true
}

# A. split-brain
fault split-brain "  action: partition
  direction: both
  selector:
    namespaces: [$ns]
    pods:
      $ns: [$STS-0]
  target:
    mode: all
    selector:
      namespaces: [$ns]
      pods:
        $ns: [$STS-1]"
both=$(grep -c '0=Master/[A-Za-z]*/Active 1=Backup/[A-Za-z]*/Active' "$E2E_OUT/s10-split-brain-states.log" || true)
multi=$(grep -c 'labelled=[^ ]*,' "$E2E_OUT/s10-split-brain-states.log" || true)
log "split-brain: both Active for ${both}s, more than one pod labelled for ${multi}s"
[ "$multi" -eq 0 ] || die "traffic was routed to two gateways during the split-brain"
wait_pair 600 || die "pair did not settle after the partition healed"
log "split-brain: pair settled after the partition"

# B. hung Master
fault hung-master "  action: partition
  direction: both
  selector:
    namespaces: [$ns]
    pods:
      $ns: [$STS-0]"
gap=$(awk '{split($2, v, "="); if (v[2] !~ /\/Active$/) {run++; if (run > max) max = run} else run = 0} END {print max + 0}' "$E2E_OUT/s10-hung-master-traffic.log")
log "hung Master: longest time not served by an Active gateway ${gap}s"
wait_pair 900 || die "pair did not recover after the Master was isolated"

{
  echo "S10 $(date -u +%FT%TZ) image=${IMAGE_TAG:-default} partition=${PARTITION_SECONDS}s"
  echo "  split-brain: both Active ${both}s, two pods labelled ${multi}s"
  echo "  hung Master: longest unserved ${gap}s"
} | tee -a "$E2E_OUT/s10-summary.txt" >&2
e2e_watch_check
log "S10 passed"
