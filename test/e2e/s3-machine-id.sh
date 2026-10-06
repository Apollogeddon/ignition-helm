#!/usr/bin/env bash
# S3: a stable machine ID mounted from a ConfigMap with extraVolumes and
# extraVolumeMounts. The gateway must start with it in place and see the same
# ID after its pod is replaced (licensing itself is checked manually).
#
# Env: IMAGE_TAG (default 8.1.53), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover
IMAGE_TAG="${IMAGE_TAG:-8.1.53}"
ID=0123456789abcdef0123456789abcdef

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s3)
e2e_require_memory "$ns"
kubectl -n "$ns" create configmap s3-machine-id --from-literal=machine-id="$ID" >/dev/null

values="$E2E_OUT/s3-values.yaml"
cat > "$values" <<'EOF'
ignition:
  extraVolumes:
    - name: machine-id
      configMap:
        name: s3-machine-id
  extraVolumeMounts:
    - name: machine-id
      mountPath: /etc/machine-id
      subPath: machine-id
      readOnly: true
EOF
args=(s3 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml" -f "$values" --set "image.tag=$IMAGE_TAG")
e2e_render_check "${args[@]}"
log "installing $IMAGE_TAG with a mounted machine ID"
e2e_install "${args[@]}"
e2e_wait_ready "$ns" 900

check() {
  local seen state
  seen=$(kubectl -n "$ns" exec $STS-0 -c gateway -- cat /etc/machine-id | tr -d '\r\n')
  state=$(kubectl -n "$ns" exec $STS-0 -c gateway -- curl -s --max-time 3 http://localhost:8088/StatusPing)
  log "$1: machine-id $seen, $state"
  [ "$seen" = "$ID" ] || die "$1: machine-id is $seen, expected $ID"
  [[ "$state" == *'"state":"RUNNING"'* ]] || die "$1: gateway not RUNNING"
}
check "first start"
uid=$(kubectl -n "$ns" get pod $STS-0 -o jsonpath='{.metadata.uid}')
kubectl -n "$ns" delete pod $STS-0 >/dev/null
for _ in $(seq 60); do
  [ "$(kubectl -n "$ns" get pod $STS-0 -o jsonpath='{.metadata.uid}' 2>/dev/null || true)" != "$uid" ] && break
  sleep 5
done
e2e_wait_ready "$ns" 900
check "after the pod was replaced"
echo "S3 $(date -u +%FT%TZ) image=$IMAGE_TAG: machine ID kept across pod replacement" >> "$E2E_OUT/s3-summary.txt"
e2e_watch_check
log "S3 passed"
