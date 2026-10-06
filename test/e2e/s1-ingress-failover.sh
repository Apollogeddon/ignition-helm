#!/usr/bin/env bash
# S1: redundant pair behind the chart Ingress. Records per-second availability
# through the Ingress and the NodePort while the Master is deleted (graceful)
# and then while its JVM is killed (crash).
#
# Env: NODE_IP (a node address), INGRESS_PORT (ingress controller HTTP NodePort),
# INGRESS_CLASS (default contour), WATCH_URL (optional), IMAGE_TAG (default chart appVersion),
# ACTIVE_ROUTING (true: enable ignition.activeRouting; results are named s1-active-*)
source "$(dirname "$0")/lib.sh"
: "${NODE_IP:?}" "${INGRESS_PORT:?}"
INGRESS_CLASS="${INGRESS_CLASS:-contour}"
CHART="$(dirname "$0")/../../charts/failover"
HOST="s1.e2e.invalid"
OBSERVE="${OBSERVE:-180}"
ACTIVE_ROUTING="${ACTIVE_ROUTING:-false}"
tag=s1; [ "$ACTIVE_ROUTING" != true ] || tag=s1-active

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s1)
e2e_require_memory "$ns"

args=(s1 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml"
  --set ignition.redundancy.enabled=true
  --set ignition.ingress.enabled=true
  --set "ignition.ingress.className=$INGRESS_CLASS"
  --set "ignition.ingress.hosts[0].host=$HOST"
  --set "ignition.ingress.hosts[0].paths[0].path=/"
  --set "ignition.ingress.hosts[0].paths[0].pathType=Prefix")
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")
[ "$ACTIVE_ROUTING" != true ] || args+=(--set ignition.activeRouting.enabled=true)
e2e_render_check "${args[@]}"

log "installing redundant pair"
"$HELM" install "${args[@]}" --wait --timeout 15m >/dev/null
e2e_watch_check

pods=($(kubectl -n "$ns" get pods -l app.kubernetes.io/name=ignition-failover -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v -- '-rotate' | sort))
[ "${#pods[@]}" -eq 2 ] || die "expected 2 gateway pods, found ${pods[*]}"
gwinfo() { kubectl -n "$ns" exec "$1" -c "${CONTAINER:-ignition}" -- curl -s --max-time 3 http://localhost:8088/system/gwinfo 2>/dev/null |
  tr ';' '\n' | grep -E '^(RedundancyStatus|RedundantState|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -; }
master=""
wait_pair() {
  local deadline=$(( $(date +%s) + 600 )) i
  while [ "$(date +%s)" -lt "$deadline" ]; do
    master=""; local ok=0
    for p in "${pods[@]}"; do
      i=$(gwinfo "$p" || true)
      case "$i" in Master/Good/Active) master=$p; ok=$((ok + 1)) ;; Backup/Good/Cold) ok=$((ok + 1)) ;; esac
    done
    if [ "$ACTIVE_ROUTING" = true ] && [ -n "$master" ]; then
      [ "$(kubectl -n "$ns" get pod "$master" -o jsonpath='{.metadata.labels.redundancy-active}' || true)" = true ] || ok=0
    fi
    [ "$ok" -eq 2 ] && [ -n "$master" ] && { log "pair healthy, master $master"; return 0; }
    sleep 5
  done
  for p in "${pods[@]}"; do log "$p: $(gwinfo "$p" || true)"; done
  die "pair did not become Master/Good/Active + Backup/Good/Cold"
}
CONTAINER=$(kubectl -n "$ns" get pod "${pods[0]}" -o jsonpath='{.spec.containers[0].name}')
wait_pair

nodeport=$(kubectl -n "$ns" get svc "ignition-failover$([ "$ACTIVE_ROUTING" != true ] || echo -active)" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
export RECORD_CURL_ARGS="--resolve $HOST:$INGRESS_PORT:$NODE_IP"
targets=(ingress="http://$HOST:$INGRESS_PORT/StatusPing" nodeport="http://$NODE_IP:$nodeport/StatusPing"
  via="http://$HOST:$INGRESS_PORT/system/gwinfo")

# observe <name> <action...>: record OBSERVE seconds, running the action after 10s
observe() {
  local name=$1; shift
  log "$name: recording ${OBSERVE}s"
  "$(dirname "$0")/record.sh" "$OBSERVE" "$E2E_OUT/$tag-$name.log" "${targets[@]}" &
  local rec=$!
  sleep 10; log "$name: $*"; "$@"
  wait "$rec"
  summarise "$E2E_OUT/$tag-$name.log"
  e2e_watch_check
}

# summarise <log>: per target, failed seconds and the longest outage. /StatusPing
# answers 200 on a cold Backup too, so "served" counts seconds the ingress was
# answered by an Active gateway; it also lists each role/state that answered.
summarise() {
  awk '{
    for (i = 2; i <= NF; i++) {
      split($i, kv, "="); k = kv[1]; v = kv[2]
      if (k == "via") {
        via[v]++; k = "served"; v = (v ~ /\/Active$/) ? "ok" : "no"
      }
      if (v ~ /^[23]|^ok$/) run[k] = 0; else { bad[k]++; run[k]++; if (run[k] > max[k]) max[k] = run[k] }
      seen[k] = 1
    }
  } END {
    for (k in seen) printf "  %-9s failed %3ds, longest outage %3ds\n", k, bad[k] + 0, max[k] + 0
    for (v in via) printf "  ingress answered by %-14s %3ds of %ds\n", v, via[v], NR
  }' "$1" | tee -a "$E2E_OUT/$tag-summary.txt" >&2
}

echo "$tag $(date -u +%FT%TZ) image=${IMAGE_TAG:-default}" >> "$E2E_OUT/$tag-summary.txt"
OBSERVE=60 observe steady true
echo "graceful (delete master $master):" >> "$E2E_OUT/$tag-summary.txt"
observe graceful kubectl -n "$ns" delete pod "$master" --wait=false
wait_pair
# a crash: the runtime SIGKILLs the container with no grace period (the JVM may
# be PID 1, which ignores SIGKILL sent from inside the container)
echo "crash (force delete master $master):" >> "$E2E_OUT/$tag-summary.txt"
observe crash kubectl -n "$ns" delete pod "$master" --grace-period=0 --force --wait=false
wait_pair
log "S1 done; results in $E2E_OUT"
