#!/usr/bin/env bash
# S07: the newer chart options together on a real gateway: a postStart lifecycle
# hook, a custom readiness command, the startupProbe, per-logger levels with
# SQLite log limits, and emptyDir size limits. The gateway must become Ready
# and each option must be in effect inside the pod.
#
# Env: IMAGE_TAG (default chart appVersion), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s07)
e2e_require_memory "$ns"

values="$E2E_OUT/s07-values.yaml"
cat > "$values" <<'EOF'
ignition:
  lifecycle:
    postStart:
      exec:
        command: ["sh", "-c", "date > /usr/local/bin/ignition/temp/poststart-ran"]
  readinessProbe:
    command: ["/config/scripts/health-check.sh", "-t", "4", "-r"]
  startupProbe:
    enabled: true
  logging:
    loggers:
      gateway.SslManager: WARN
      perspective: INFO
    sqlite:
      entryLimit: 20000
  emptyDirSizeLimit:
    logs: 256Mi
    temp: 512Mi
EOF
args=(s07 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml" -f "$values")
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")
e2e_render_check "${args[@]}"
log "installing with lifecycle, custom readiness, startupProbe, loggers and size limits"
e2e_install "${args[@]}"
e2e_wait_ready "$ns" 900

failed=""
in_pod() { kubectl -n "$ns" exec $STS-0 -c gateway -- sh -c "$1" 2>/dev/null; }
spec() { kubectl -n "$ns" get pod $STS-0 -o jsonpath="$1"; }

[ -n "$(in_pod 'cat /usr/local/bin/ignition/temp/poststart-ran')" ] || failed="$failed postStart"
[ "$(spec '{.spec.containers[0].readinessProbe.exec.command}')" = '["/config/scripts/health-check.sh","-t","4","-r"]' ] || failed="$failed readiness-command"
[ -n "$(spec '{.spec.containers[0].startupProbe.exec.command}')" ] || failed="$failed startupProbe"
in_pod 'grep -q "<logger name=\"gateway.SslManager\" level=\"WARN\" />" /usr/local/bin/ignition/data/logback.xml' || failed="$failed logger"
in_pod 'grep -q "<entryLimit>20000</entryLimit>" /usr/local/bin/ignition/data/logback.xml' || failed="$failed sqlite"
in_pod 'grep -q "gateway.SslManager\" level=\"DEBUG" /usr/local/bin/ignition/data/logback.xml' && failed="$failed SslManager-still-DEBUG"
[ "$(spec '{.spec.volumes[?(@.name=="ignition-failover-logs")].emptyDir.sizeLimit}')" = 256Mi ] || failed="$failed logs-sizeLimit"
restarts=$(spec '{.status.containerStatuses[0].restartCount}')
[ "$restarts" = 0 ] || failed="$failed restarted-$restarts"
state=$(in_pod 'curl -s --max-time 3 http://localhost:8088/StatusPing')

echo "S07 $(date -u +%FT%TZ) image=${IMAGE_TAG:-default}: ${state}; failed:${failed:- none}" | tee -a "$E2E_OUT/s07-summary.txt" >&2
[ -z "$failed" ] || die "S07:$failed"
e2e_watch_check
log "S07 passed"
