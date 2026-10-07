#!/usr/bin/env bash
# S02: upgrade from a released chart version to the working tree.
#   failover (default): a redundant pair; the StatefulSet must replace the
#     Backup (pod 1) before the Master (pod 0) and the pair must come back
#     healthy.
#   scaleout (CHART_KIND=scaleout): one frontend and a standalone backend (two
#     gateways, within the staging budget); both StatefulSets must be adopted
#     and the frontend must reconnect to the backend over the Gateway Network.
# StatefulSets whose spec.serviceName changes (4.0.0 and earlier used the main
# Service, later versions the -headless one) are deleted with --cascade=orphan
# first, as the chart READMEs describe; their pods and PVCs keep running and the
# upgraded StatefulSets adopt them. The time user traffic is not served by an
# Active gateway is recorded through the NodePort.
#
# Env: NODE_IP, CHART_KIND (failover or scaleout), FROM_VERSION (default
# 4.0.0), CHART_REPO (default the published repo), IMAGE_TAG (default chart
# appVersion), APP_NAME (applicationName, e.g. my-gateway), FROM_SET
# (extra --set for the starting install, e.g.
# ignition.securityContext.runAsUser=2003), UPGRADE_SET (extra
# --set for the upgrade, e.g. ignition.activeRouting.enabled=true), WATCH_URL
# (optional)
source "$(dirname "$0")/lib.sh"
: "${NODE_IP:?}"
CHART_KIND="${CHART_KIND:-failover}"
FROM_VERSION="${FROM_VERSION:-4.0.0}"
CHART_REPO="${CHART_REPO:-https://apollogeddon.github.io/ignition-helm}"
CHART="$(dirname "$0")/../../charts/$CHART_KIND"
NAME="${APP_NAME:-ignition-$CHART_KIND}"
tag=s02; [ "$CHART_KIND" = failover ] || tag="s02-$CHART_KIND"

case "$CHART_KIND" in
  failover)
    values=(-f "$(dirname "$0")/values/small.yaml" --set ignition.redundancy.enabled=true
      --set ignition.service.type=NodePort) ;;
  scaleout)
    values=(-f "$(dirname "$0")/values/small-scaleout.yaml" --set frontend.service.type=NodePort) ;;
  *) die "CHART_KIND must be failover or scaleout" ;;
esac
if [ "$CHART_KIND" = failover ]; then
  statefulsets=("$NAME"); front="$NAME"
else
  statefulsets=("$NAME-backend" "$NAME-frontend"); front="$NAME-frontend"
fi

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns "$tag")
e2e_require_memory "$ns"

common=(-n "$ns" "${values[@]}")
[ -z "${APP_NAME:-}" ] || common+=(--set "applicationName=$APP_NAME")
[ -z "${IMAGE_TAG:-}" ] || common+=(--set "image.tag=$IMAGE_TAG")

from=(s02 "ignition-$CHART_KIND" --repo "$CHART_REPO" --version "$FROM_VERSION" "${common[@]}")
for s in ${FROM_SET:-}; do from+=(--set "$s"); done
e2e_render_check "${from[@]}"
log "installing $CHART_KIND $FROM_VERSION from $CHART_REPO"
e2e_install "${from[@]}"
e2e_wait_ready "$ns" 900

gwinfo() { kubectl -n "$ns" exec "$1" -c gateway -- curl -s --max-time 3 http://localhost:8088/system/gwinfo 2>/dev/null |
  tr ';' '\n' | grep -E '^(RedundancyStatus|RedundantState|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -; }
wait_pair() {
  local deadline=$(( $(date +%s) + 900 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    [ "$(gwinfo "$NAME-0" || true)" = Master/Good/Active ] && [ "$(gwinfo "$NAME-1" || true)" = Backup/Good/Cold ] && return 0
    sleep 5
  done
  die "pair not healthy: $NAME-0 $(gwinfo "$NAME-0" || true), $NAME-1 $(gwinfo "$NAME-1" || true)"
}
# the frontend's outgoing Gateway Network connection to the backend is Running
# in its current pod's log: the container log, or logs/wrapper.log for chart
# versions that do not send the wrapper log to stdout (4.0.0 and earlier)
frontend_connected() {
  local logs running
  logs=$(kubectl -n "$ns" logs "$front-0" -c gateway 2>/dev/null || true
    kubectl -n "$ns" exec "$front-0" -c gateway -- sh -c 'cat /usr/local/bin/ignition/logs/wrapper.log 2>/dev/null' 2>/dev/null || true)
  # collect first and tolerate each source failing: with pipefail, a missing
  # wrapper.log (newer charts) or a writer cut off by grep -q would otherwise
  # make a match look like a failure
  running=$(grep -E "to Running" <<< "$logs" | grep -cF "$NAME-backend-0" || true)
  [ "${running:-0}" -gt 0 ]
}
wait_frontend() {
  local deadline=$(( $(date +%s) + 600 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do frontend_connected && return 0; sleep 10; done
  die "the frontend did not reconnect to the backend over the Gateway Network"
}
pods() { kubectl -n "$ns" get pods -l "app.kubernetes.io/instance=s02" -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.uid}{"\n"}{end}' | grep -E "^$NAME(-frontend|-backend)?-[0-9]+=" | sort; }

if [ "$CHART_KIND" = failover ]; then wait_pair; else wait_frontend; fi
log "healthy on $FROM_VERSION"
before=$(pods)

upgrade=(s02 "$CHART" "${common[@]}")
for s in ${UPGRADE_SET:-}; do upgrade+=(--set "$s"); done
e2e_render_check "${upgrade[@]}"
svc=$front; [[ " ${UPGRADE_SET:-} " != *" ignition.activeRouting.enabled=true "* ]] || svc=$NAME-active
nodeport=$(kubectl -n "$ns" get svc "$front" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

"$(dirname "$0")/record.sh" 1200 "$E2E_OUT/$tag-upgrade.log" via="http://$NODE_IP:$nodeport/system/gwinfo" &
rec=$!
sleep 5
start=$(date +%s)
rendered=$("$HELM" template "${upgrade[@]}" | tr -d '\r')
for sts in "${statefulsets[@]}"; do
  current=$(kubectl -n "$ns" get sts "$sts" -o jsonpath='{.spec.serviceName}')
  wanted=$(awk -v n="$sts" '/^kind: StatefulSet/ {s = 1; m = 0} s && $1 == "name:" && $2 == n {m = 1} m && /^  serviceName:/ {print $2; exit}' <<< "$rendered")
  if [ -n "$wanted" ] && [ "$current" != "$wanted" ]; then
    log "$sts serviceName changes ($current -> $wanted): deleting the StatefulSet with --cascade=orphan"
    kubectl -n "$ns" delete sts "$sts" --cascade=orphan >/dev/null
  fi
done
log "upgrading to the working tree ${UPGRADE_SET:+(${UPGRADE_SET})}"
e2e_install "${upgrade[@]}"
# the -active Service takes over the configured nodePorts only if they are
# fixed; follow whichever Service now has a NodePort
if [ "$svc" != "$front" ]; then
  kill "$rec" 2>/dev/null; wait "$rec" 2>/dev/null || true
  nodeport=$(kubectl -n "$ns" get svc "$svc" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
  "$(dirname "$0")/record.sh" 1200 "$E2E_OUT/$tag-upgrade.log" via="http://$NODE_IP:$nodeport/system/gwinfo" &
  rec=$!
fi
for sts in "${statefulsets[@]}"; do
  for _ in $(seq 240); do
    read -r cur upd ready total <<< "$(kubectl -n "$ns" get sts "$sts" \
      -o jsonpath='{.status.currentRevision} {.status.updateRevision} {.status.readyReplicas} {.status.replicas}' || true)"
    [ -n "$cur" ] && [ "$cur" = "$upd" ] && [ "${ready:-0}" = "${total:-x}" ] && break
    sleep 5
  done
done
if [ "$CHART_KIND" = failover ]; then wait_pair; else wait_frontend; fi
log "upgrade rolled out and healthy in $(( $(date +%s) - start ))s"
sleep 30
kill "$rec" 2>/dev/null; wait "$rec" 2>/dev/null || true

after=$(pods)
while IFS='=' read -r pod uid; do
  [ -n "$uid" ] || continue
  grep -qF "$uid" <<< "$after" && die "$pod was not replaced by the upgrade"
done <<< "$before"
order=""
if [ "$CHART_KIND" = failover ]; then
  t0=$(kubectl -n "$ns" get pod "$NAME-0" -o jsonpath='{.metadata.creationTimestamp}')
  t1=$(kubectl -n "$ns" get pod "$NAME-1" -o jsonpath='{.metadata.creationTimestamp}')
  [[ "$t1" < "$t0" ]] || die "Master (pod 0) was replaced before the Backup (pod 1)"
  order="pod 1 replaced at $t1, pod 0 at $t0"
fi

{
  echo "S02 $(date -u +%FT%TZ) chart=$CHART_KIND from=$FROM_VERSION name=$NAME image=${IMAGE_TAG:-default} from-set=${FROM_SET:-none} set=${UPGRADE_SET:-none}"
  awk '{split($2, v, "="); if (v[2] ~ /\/Active$/) {ok++; run = 0} else {bad++; run++; if (run > max) max = run}}
    END {printf "  served %ds, not served %ds, longest gap %ds\n", ok, bad, max}' "$E2E_OUT/$tag-upgrade.log"
  [ -z "$order" ] || echo "  $order"
} | tee -a "$E2E_OUT/$tag-summary.txt" >&2
awk '{s=$2} s!=p {print; p=s}' "$E2E_OUT/$tag-upgrade.log" > "$E2E_OUT/$tag-transitions.txt"
e2e_watch_check
log "S02 passed"
