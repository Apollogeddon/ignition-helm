#!/usr/bin/env bash
# S8: a gateway that cannot finish commissioning (EULA not accepted) must not
# become Ready, and liveness must not restart it in a loop. Records the
# /StatusPing body each second for each Ignition version.
#
# Env: IMAGE_TAGS (default "8.3.1 8.1.53"), OBSERVE (seconds, default 240), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/failover"
IMAGE_TAGS="${IMAGE_TAGS:-8.3.1 8.1.53}"
OBSERVE="${OBSERVE:-240}"

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s8)
failed=""

for tag in $IMAGE_TAGS; do
  e2e_require_memory "$ns"
  args=(s8 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml" --set "image.tag=$tag"
    --set-string ignition.config.ACCEPT_IGNITION_EULA=N
    --set ignition.readinessProbe.initialDelaySeconds=30)
  e2e_render_check "${args[@]}"
  log "$tag: installing an uncommissioned gateway"
  "$HELM" install "${args[@]}" >/dev/null
  kubectl -n "$ns" wait pod/ignition-failover-0 --for=jsonpath='{.status.phase}'=Running --timeout=10m >/dev/null

  out="$E2E_OUT/s8-$tag.log"; : > "$out"
  ready=0; end=$(( $(date +%s) + OBSERVE ))
  while [ "$(date +%s)" -lt "$end" ]; do
    body=$(kubectl -n "$ns" exec ignition-failover-0 -c gateway -- curl -s --max-time 2 http://localhost:8088/StatusPing 2>/dev/null || true)
    r=$(kubectl -n "$ns" get pod ignition-failover-0 -o jsonpath='{.status.containerStatuses[0].ready} {.status.containerStatuses[0].restartCount}' || echo "api-error -")
    echo "$(date -u +%H:%M:%S) ready/restarts=$r body=${body:-none}" >> "$out"
    [ "${r%% *}" = "true" ] && ready=$((ready + 1))
    sleep 2
  done
  restarts=$(kubectl -n "$ns" get pod ignition-failover-0 -o jsonpath='{.status.containerStatuses[0].restartCount}' ||
    kubectl -n "$ns" get pod ignition-failover-0 -o jsonpath='{.status.containerStatuses[0].restartCount}')
  log "$tag: bodies seen: $(cut -d' ' -f4- "$out" | sort | uniq -c | tr -s ' \n' ' ')"
  log "$tag: ready samples $ready, restarts $restarts"
  [ "$ready" -eq 0 ] || failed="$failed $tag:became-ready"
  [ "$restarts" -eq 0 ] || failed="$failed $tag:restarted"
  e2e_watch_check
  "$HELM" uninstall s8 -n "$ns" --wait >/dev/null
  kubectl -n "$ns" delete pvc --all --wait=true >/dev/null
done

[ -z "$failed" ] || die "S8:$failed"
log "S8 passed"
