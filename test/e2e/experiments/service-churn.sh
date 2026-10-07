#!/usr/bin/env bash
# Experiment: does creating and deleting Services make NodePorts on the node
# briefly stop answering? (An S02 run saw the staging dashboard miss checks a
# few seconds after kube-proxy rewrote its nftables rules.)
#
# A probe pod in a test namespace samples every RECORD_INTERVAL_MS (default
# 200) a test NodePort (a tiny web server in the test namespace) and, if
# WATCH_NODEPORT is set, another NodePort on the node (e.g. the staging
# dashboard, read-only GETs). The same targets are also sampled from this
# machine once a second. Phases: BASELINE seconds quiet, CHURN Services created
# and deleted in the test namespace, then BASELINE seconds quiet again.
# kube-proxy's log for the window is saved next to the results.
#
# Env: NODE_IP, WATCH_NODEPORT (optional, e.g. 30088), BASELINE (default 60),
# CHURN (Service create/delete cycles, default 20)
source "$(dirname "$0")/../lib.sh"
: "${NODE_IP:?}"
BASELINE="${BASELINE:-60}"
CHURN="${CHURN:-20}"
export RECORD_INTERVAL_MS="${RECORD_INTERVAL_MS:-200}"

e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns churn)
e2e_require_memory "$ns"

log "starting a test web server behind a NodePort"
e2e_retry kubectl -n "$ns" apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels: {app: churn-web}
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: web
      image: busybox:1.36
      command: ["sh", "-c", "mkdir -p /tmp/w && echo ok > /tmp/w/index.html && exec httpd -f -p 8080 -h /tmp/w"]
      resources:
        requests: {cpu: 10m, memory: 8Mi}
        limits: {cpu: 100m, memory: 32Mi}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: NodePort
  selector: {app: churn-web}
  ports: [{port: 8080, targetPort: 8080}]
EOF
e2e_retry kubectl -n "$ns" wait pod/web --for=condition=Ready --timeout=5m >/dev/null
port=$(kubectl -n "$ns" get svc web -o jsonpath='{.spec.ports[0].nodePort}')

targets=(test="http://$NODE_IP:$port/")
[ -z "${WATCH_NODEPORT:-}" ] || targets+=(dashboard="http://$NODE_IP:$WATCH_NODEPORT/StatusPing")
churn_secs=$(( CHURN * 6 ))
total=$(( BASELINE * 2 + churn_secs + 30 ))
from=$(date -u +%Y-%m-%dT%H:%M:%SZ)

e2e_probe_start "$ns" churn "$total" "${targets[@]}"
RECORD_INTERVAL_MS="" "$(dirname "$0")/../record.sh" "$total" "$E2E_OUT/churn-outside.log" "${targets[@]}" &
rec=$!

log "baseline ${BASELINE}s"
sleep "$BASELINE"
t_churn=$(date -u +%H:%M:%S)
log "churn: $CHURN Service create/delete cycles"
for i in $(seq "$CHURN"); do
  e2e_retry kubectl -n "$ns" create service nodeport "churn-$i" --tcp=8081:8081 >/dev/null
  sleep 3
  e2e_retry kubectl -n "$ns" delete service "churn-$i" >/dev/null
  sleep 3
done
t_quiet=$(date -u +%H:%M:%S)
log "quiet ${BASELINE}s"
wait "$rec" 2>/dev/null || true
e2e_probe_collect "$ns" churn "$E2E_OUT/churn-inside.log"
kubectl -n kube-system logs ds/kube-proxy --since-time="$from" > "$E2E_OUT/churn-kube-proxy.log" 2>&1 || true

# count failed samples per target and phase (baseline / churn / quiet)
summary() {
  awk -v c="$t_churn" -v q="$t_quiet" '{
    t = substr($1, 1, 8); p = (t < c) ? "baseline" : (t < q) ? "churn" : "quiet"
    for (i = 2; i <= NF; i++) { split($i, kv, "="); n[p" "kv[1]]++; if (kv[2] !~ /^[23]/) f[p" "kv[1]]++ }
  } END { for (k in n) printf "  %-22s %4d of %4d samples failed\n", k, f[k] + 0, n[k] }' "$1" | sort
}
{
  echo "service churn $(date -u +%FT%TZ): churn ${t_churn}-${t_quiet}, ${CHURN} cycles, inside every ${RECORD_INTERVAL_MS}ms"
  echo " inside the cluster:"; summary "$E2E_OUT/churn-inside.log"
  echo " from the test machine:"; summary "$E2E_OUT/churn-outside.log"
  echo " kube-proxy rule syncs in the window: $(grep -c 'nftables\|Syncing\|sync' "$E2E_OUT/churn-kube-proxy.log" || true)"
} | tee "$E2E_OUT/churn-summary.txt" >&2
grep -v ' test=200\( dashboard=200\)\?$' "$E2E_OUT/churn-inside.log" > "$E2E_OUT/churn-inside-failures.log" || true
e2e_watch_check
log "experiment done; failures inside the cluster are in churn-inside-failures.log"
