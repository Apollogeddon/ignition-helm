#!/usr/bin/env bash
# S3: a scaleout frontend connects to its backend over the Gateway Network.
# Installs one frontend and a standalone backend, waits for both, then checks
# the gateway logs for the connection. Logs and matched lines are saved.
#
# Env: IMAGE_TAG (default chart appVersion), WATCH_URL (optional), SETTLE (seconds, default 120)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/scaleout"
NAME=ignition-scaleout
SETTLE="${SETTLE:-120}"

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s3)
e2e_require_memory "$ns"

values="$E2E_OUT/s3-values.yaml"
cat > "$values" <<'EOF'
frontend:
  resources:
    requests: {cpu: 100m, memory: 200Mi}
    limits: {cpu: "2", memory: 2Gi}
backend:
  resources:
    requests: {cpu: 100m, memory: 200Mi}
    limits: {cpu: "2", memory: 2Gi}
EOF
args=(s3 "$CHART" -n "$ns" -f "$values")
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")
e2e_render_check "${args[@]}"
log "installing scaleout (1 frontend, standalone backend)"
e2e_install "${args[@]}"
e2e_wait_ready "$ns" 900
log "both gateways Ready; letting the Gateway Network settle for ${SETTLE}s"
sleep "$SETTLE"

backend_host=$(kubectl -n "$ns" get pod $NAME-frontend-0 -o jsonpath='{.spec.containers[0].env[?(@.name=="GATEWAY_NETWORK_0_HOST")].value}')
for c in frontend backend; do
  kubectl -n "$ns" logs $NAME-$c-0 -c gateway > "$E2E_OUT/s3-$c.log" 2>&1 || true
  grep -iE 'gateway ?network|metro|websocket|remote (gateway|server)|connection' "$E2E_OUT/s3-$c.log" > "$E2E_OUT/s3-$c-gan.txt" || true
  log "$c: $(wc -l < "$E2E_OUT/s3-$c-gan.txt") Gateway Network lines (saved to s3-$c-gan.txt)"
done
log "frontend GATEWAY_NETWORK_0_HOST=$backend_host"

# the frontend's outgoing connection to the backend reached Running, the
# backend registered the frontend, and neither gateway is still named by an
# unexpanded "$(GATEWAY_SYSTEM_NAME)"
running=$(grep -E "to Running" "$E2E_OUT/s3-frontend-gan.txt" | grep -F "$backend_host" | tail -1 || true)
incoming=$(grep -E "Registering connection: $NAME-frontend-0|$NAME-frontend-0 connection status has been updated from .* to Running" "$E2E_OUT/s3-backend-gan.txt" | tail -1 || true)
# grep -c exits 1 when it counts nothing, which pipefail would turn into a failure
literal=$({ grep -ciF '$(gateway_system_name)' "$E2E_OUT/s3-frontend.log" "$E2E_OUT/s3-backend.log" || true; } | awk -F: '{n += $NF} END {print n + 0}')
log "frontend -> backend Running: ${running:+yes}; backend saw the frontend: ${incoming:+yes}; unexpanded system names: $literal"
{
  echo "S3 $(date -u +%FT%TZ) image=${IMAGE_TAG:-default} backend=$backend_host"
  echo "  outgoing Running: ${running:-no}"
  echo "  backend incoming: ${incoming:-no}"
  echo "  unexpanded system name lines: $literal"
} >> "$E2E_OUT/s3-summary.txt"
[ -n "$running" ] || die "the frontend's connection to $backend_host never reached Running"
[ -n "$incoming" ] || die "the backend did not register the frontend's connection"
[ "$literal" -eq 0 ] || die 'a gateway is named by an unexpanded $(GATEWAY_SYSTEM_NAME)'
e2e_watch_check
log "S3 passed"
