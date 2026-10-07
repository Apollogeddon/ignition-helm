#!/usr/bin/env bash
# S2: upgrade a redundant pair from a released chart version to the working
# tree. The StatefulSet must replace the Backup (pod 1) before the Master
# (pod 0), the pair must come back healthy, and the time user traffic is not
# served by an Active gateway is recorded through the NodePort.
#
# Env: NODE_IP, FROM_VERSION (default 4.0.0), CHART_REPO (default the published
# repo), IMAGE_TAG (default chart appVersion), FROM_SET (extra --set for the
# starting install), UPGRADE_SET (extra --set for the upgrade, e.g.
# ignition.activeRouting.enabled=true), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
: "${NODE_IP:?}"
CHART="$(dirname "$0")/../../charts/failover"
FROM_VERSION="${FROM_VERSION:-4.0.0}"
CHART_REPO="${CHART_REPO:-https://apollogeddon.github.io/ignition-helm}"
STS=ignition-failover

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s2)
e2e_require_memory "$ns"

common=(-n "$ns" -f "$(dirname "$0")/values/small.yaml" --set ignition.redundancy.enabled=true
  --set ignition.service.type=NodePort)
[ -z "${IMAGE_TAG:-}" ] || common+=(--set "image.tag=$IMAGE_TAG")

from=(s2 ignition-failover --repo "$CHART_REPO" --version "$FROM_VERSION" "${common[@]}")
for s in ${FROM_SET:-}; do from+=(--set "$s"); done
e2e_render_check "${from[@]}"
log "installing $FROM_VERSION from $CHART_REPO"
e2e_install "${from[@]}"
e2e_wait_ready "$ns" 900

gwinfo() { kubectl -n "$ns" exec "$1" -c gateway -- curl -s --max-time 3 http://localhost:8088/system/gwinfo 2>/dev/null |
  tr ';' '\n' | grep -E '^(RedundancyStatus|RedundantState|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -; }
wait_pair() {
  local deadline=$(( $(date +%s) + 900 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    [ "$(gwinfo $STS-0 || true)" = Master/Good/Active ] && [ "$(gwinfo $STS-1 || true)" = Backup/Good/Cold ] && return 0
    sleep 5
  done
  die "pair not healthy: $STS-0 $(gwinfo $STS-0 || true), $STS-1 $(gwinfo $STS-1 || true)"
}
wait_pair
log "pair healthy on $FROM_VERSION"
before=$(kubectl -n "$ns" get pod $STS-0 $STS-1 -o jsonpath='{.items[*].metadata.uid}')

upgrade=(s2 "$CHART" "${common[@]}")
for s in ${UPGRADE_SET:-}; do upgrade+=(--set "$s"); done
e2e_render_check "${upgrade[@]}"
svc=$STS; [[ " ${UPGRADE_SET:-} " != *" ignition.activeRouting.enabled=true "* ]] || svc=$STS-active
nodeport=$(kubectl -n "$ns" get svc $STS -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

"$(dirname "$0")/record.sh" 1200 "$E2E_OUT/s2-upgrade.log" via="http://$NODE_IP:$nodeport/system/gwinfo" &
rec=$!
sleep 5
start=$(date +%s)
# spec.serviceName cannot be changed on a StatefulSet (4.0.0 and earlier use
# the main Service, later versions the -headless one). Delete only the
# StatefulSet object; its pods and PVCs keep running and the upgraded
# StatefulSet adopts them, then rolls them Backup first.
current=$(kubectl -n "$ns" get sts $STS -o jsonpath='{.spec.serviceName}')
wanted=$("$HELM" template "${upgrade[@]}" | tr -d '\r' | awk '/^kind: StatefulSet/ {s = 1} s && /^  serviceName:/ {print $2; exit}')
if [ "$current" != "$wanted" ]; then
  log "serviceName changes ($current -> $wanted): deleting the StatefulSet with --cascade=orphan"
  kubectl -n "$ns" delete sts $STS --cascade=orphan >/dev/null
fi
log "upgrading to the working tree ${UPGRADE_SET:+(${UPGRADE_SET})}"
e2e_install "${upgrade[@]}"
# the -active Service takes over the configured nodePorts only if they are
# fixed; follow whichever Service now has a NodePort
if [ "$svc" != "$STS" ]; then
  kill "$rec" 2>/dev/null; wait "$rec" 2>/dev/null || true
  nodeport=$(kubectl -n "$ns" get svc "$svc" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
  "$(dirname "$0")/record.sh" 1200 "$E2E_OUT/s2-upgrade.log" via="http://$NODE_IP:$nodeport/system/gwinfo" &
  rec=$!
fi
for _ in $(seq 240); do
  [ "$(kubectl -n "$ns" get sts $STS -o jsonpath='{.status.currentRevision}')" = "$(kubectl -n "$ns" get sts $STS -o jsonpath='{.status.updateRevision}')" ] &&
    [ "$(kubectl -n "$ns" get sts $STS -o jsonpath='{.status.readyReplicas}')" = 2 ] && break
  sleep 5
done
wait_pair
log "upgrade rolled out and pair healthy in $(( $(date +%s) - start ))s"
sleep 30
kill "$rec" 2>/dev/null; wait "$rec" 2>/dev/null || true

after=$(kubectl -n "$ns" get pod $STS-0 $STS-1 -o jsonpath='{.items[*].metadata.uid}')
for u in $before; do case " $after " in *" $u "*) die "pod $u was not replaced by the upgrade" ;; esac; done
t0=$(kubectl -n "$ns" get pod $STS-0 -o jsonpath='{.metadata.creationTimestamp}')
t1=$(kubectl -n "$ns" get pod $STS-1 -o jsonpath='{.metadata.creationTimestamp}')
[[ "$t1" < "$t0" ]] || die "Master (pod 0) was replaced before the Backup (pod 1)"

{
  echo "S2 $(date -u +%FT%TZ) from=$FROM_VERSION image=${IMAGE_TAG:-default} set=${UPGRADE_SET:-none}"
  awk '{split($2, v, "="); if (v[2] ~ /\/Active$/) {ok++; run = 0} else {bad++; run++; if (run > max) max = run}}
    END {printf "  served %ds, not served %ds, longest gap %ds\n", ok, bad, max}' "$E2E_OUT/s2-upgrade.log"
  echo "  pod 1 replaced at $t1, pod 0 at $t0"
} | tee -a "$E2E_OUT/s2-summary.txt" >&2
awk '{s=$2} s!=p {print; p=s}' "$E2E_OUT/s2-upgrade.log" > "$E2E_OUT/s2-transitions.txt"
e2e_watch_check
log "S2 passed"
