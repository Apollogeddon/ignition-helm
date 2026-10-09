#!/usr/bin/env bash
# S08: the gateway log goes to the container log, not to an unrotated
# logs/wrapper.log on the logs emptyDir (the cause of "Usage of EmptyDir volume
# ... exceeds the limit" evictions). For each Ignition version, installs a
# standalone gateway with the default (wrapperLogToStdout) and checks that
# wrapper.log is absent or not growing while `kubectl logs` shows gateway
# output; then repeats with wrapperLogToStdout=false to show the difference.
#
# Env: IMAGE_TAGS (default "8.3.1 8.1.53"), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/failover"
IMAGE_TAGS="${IMAGE_TAGS:-8.3.1 8.1.53}"

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s08)
failed=""
out="$E2E_OUT/s08-summary.txt"

wrapper_size() {
  kubectl -n "$ns" exec ignition-failover-0 -c gateway -- sh -c \
    'stat -c %s /usr/local/bin/ignition/logs/wrapper.log 2>/dev/null || echo 0' 2>/dev/null | tr -dc '0-9'
}

for tag in $IMAGE_TAGS; do
  for stdout in true false; do
    e2e_require_memory "$ns"
    args=(s08 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml" --set "image.tag=$tag"
      --set "ignition.logging.wrapperLogToStdout=$stdout")
    e2e_render_check "${args[@]}"
    log "$tag wrapperLogToStdout=$stdout: installing"
    e2e_install "${args[@]}"
    e2e_wait_ready "$ns" 900

    # let the gateway log for a while after start-up
    first=$(wrapper_size); sleep 60; second=$(wrapper_size)
    lines=$(kubectl -n "$ns" logs ignition-failover-0 -c gateway --since=10m 2>/dev/null | grep -c . || true)
    files=$(kubectl -n "$ns" exec ignition-failover-0 -c gateway -- sh -c 'ls -la /usr/local/bin/ignition/logs' 2>/dev/null | awk 'NR>1 {print $NF"="$5}' | paste -sd' ' -)
    echo "$tag wrapperLogToStdout=$stdout: wrapper.log ${first:-0} -> ${second:-0} bytes over 60s; kubectl logs lines (10m): $lines; logs dir: $files" | tee -a "$out" >&2

    if [ "$stdout" = true ]; then
      [ "${second:-0}" -le "${first:-0}" ] || failed="$failed $tag:wrapper.log-grows"
      [ "$lines" -gt 20 ] || failed="$failed $tag:no-container-log"
    fi
    e2e_watch_check
    e2e_retry "$HELM" uninstall s08 -n "$ns" --wait >/dev/null || true
    kubectl -n "$ns" delete pvc --all --wait=true >/dev/null
  done
done

[ -z "$failed" ] || die "S08:$failed"
log "S08 passed"
