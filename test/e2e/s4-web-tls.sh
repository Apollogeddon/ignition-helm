#!/usr/bin/env bash
# S4: web TLS (ssl.enabled). A certificate for the gateway is issued in the test
# namespace by the chart's own GAN CA Issuer as a PKCS#12 keystore; the gateway
# must serve it on its HTTPS port and stay healthy.
#
# Env: IMAGE_TAG (default chart appVersion), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover
CN="s4-web.e2e.invalid"

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s4)
e2e_require_memory "$ns"

args=(s4 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml"
  --set ignition.ssl.enabled=true --set ignition.ssl.secretName=s4-web-tls)
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")
e2e_render_check "${args[@]}"
log "installing with ssl.enabled"
e2e_install "${args[@]}"

# the pod waits for the web certificate secret; issue it from the chart's CA
pass=$(kubectl -n "$ns" get secret $STS-secrets -o jsonpath='{.data.IGNITION_WEB_KEYSTORE_PASSWORD}' | base64 -d)
kubectl -n "$ns" create secret generic s4-web-keystore-pass --from-literal=password="$pass" >/dev/null
kubectl -n "$ns" apply -f - >/dev/null <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: s4-web
spec:
  secretName: s4-web-tls
  commonName: $CN
  dnsNames: [$CN]
  issuerRef:
    name: $STS-gan-issuer
    kind: Issuer
  keystores:
    pkcs12:
      create: true
      passwordSecretRef:
        name: s4-web-keystore-pass
        key: password
EOF
kubectl -n "$ns" wait certificate s4-web --for=condition=Ready --timeout=5m >/dev/null
log "web certificate issued"
e2e_wait_ready "$ns" 900

served=$(kubectl -n "$ns" exec $STS-0 -c gateway -- sh -c 'curl -skv --max-time 5 https://localhost:8043/StatusPing 2>&1' |
  grep -iE 'subject:|"state"' | tr -s ' ' | paste -sd' ' -)
log "HTTPS: $served"
grep -q "CN=$CN" <<< "$served" || grep -q "CN = $CN" <<< "$served" || die "gateway does not serve the issued certificate"
grep -q '"state":"RUNNING"' <<< "$served" || die "gateway not RUNNING over HTTPS"
echo "S4 $(date -u +%FT%TZ) image=${IMAGE_TAG:-default}: $served" >> "$E2E_OUT/s4-summary.txt"
e2e_watch_check
log "S4 passed"
