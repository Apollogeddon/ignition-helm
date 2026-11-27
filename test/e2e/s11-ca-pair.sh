#!/usr/bin/env bash
# S11: a redundant pair with activeRouting and web TLS under a CA-type issuer,
# with non-default passwords from existingSecret, then a rolling upgrade that
# changes the pair's modules.
#   1. the pair reaches Master/Good/Active + Backup/Good/Cold: the Gateway
#      Network keystores open with the Secret's GAN password and the peers trust
#      each other although the issuer is a CA (not self-signed)
#   2. the active label is on the Master alone and the <name>-active Service
#      has it as its endpoint
#   3. the gateway serves the web certificate on 8043 (the web keystore
#      password), and on 8.3 the JDBC driver modules started
#   4. an upgrade that adds a module (UPGRADE_MODULE, default vision) finishes:
#      the new Backup is Incompatible with the old Master until the Master is
#      replaced too, and the pair is Good again afterwards
#
# Env: CA_ISSUER (a CA-type ClusterIssuer; default: a CA Issuer created in the
# test namespace), IMAGE_TAG (default chart appVersion), WATCH_URL (optional),
# UPGRADE_MODULE (empty skips step 4)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover
CN="s11-web.e2e.invalid"
UPGRADE_MODULE="${UPGRADE_MODULE-vision}"
JDBC_MODULES=(com.inductiveautomation.jdbc.postgresql com.inductiveautomation.jdbc.mssql com.inductiveautomation.jdbc.mariadb)

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s11)
e2e_require_memory "$ns"
summary="$E2E_OUT/s11-summary.txt"
echo "s11 $(date -u +%FT%TZ) image=${IMAGE_TAG:-default} issuer=${CA_ISSUER:-namespaced}" >> "$summary"

# the issuer: a CA ClusterIssuer the cluster provides, or a CA Issuer here,
# whose own CA is issued by a self-signed Issuer
if [ -n "${CA_ISSUER:-}" ]; then
  issuer_kind=ClusterIssuer issuer=$CA_ISSUER
else
  issuer_kind=Issuer issuer=s11-ca
  kubectl -n "$ns" apply -f - >/dev/null <<'EOF'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: s11-bootstrap
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: s11-ca
spec:
  isCA: true
  commonName: s11-e2e-ca
  secretName: s11-ca
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {name: s11-bootstrap, kind: Issuer}
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: s11-ca
spec:
  ca:
    secretName: s11-ca
EOF
  kubectl -n "$ns" wait certificate s11-ca --for=condition=Ready --timeout=5m >/dev/null
  kubectl -n "$ns" wait issuer s11-ca --for=condition=Ready --timeout=5m >/dev/null
fi
e2e_issuer_is_ca "$ns" "$issuer_kind" "$issuer" || die "$issuer_kind $issuer is not a CA issuer"
log "issuing from CA $issuer_kind $issuer"

# passwords that are neither Ignition's defaults (metro, ignition) nor the
# other scenarios', in a Secret of the test's own
gan_pass="s11-gan-$RANDOM$RANDOM" web_pass="s11-web-$RANDOM$RANDOM"
kubectl -n "$ns" create secret generic s11-gateway \
  --from-literal=GATEWAY_ADMIN_PASSWORD="s11-admin-$RANDOM$RANDOM" \
  --from-literal=IGNITION_GAN_KEYSTORE_PASSWORD="$gan_pass" \
  --from-literal=IGNITION_WEB_KEYSTORE_PASSWORD="$web_pass" >/dev/null
kubectl -n "$ns" create secret generic s11-web-keystore-pass --from-literal=password="$web_pass" >/dev/null

# the web certificate, a PKCS#12 keystore under the web password, from the CA
kubectl -n "$ns" apply -f - >/dev/null <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: s11-web
spec:
  secretName: s11-web-tls
  commonName: $CN
  dnsNames: [$CN]
  issuerRef: {name: $issuer, kind: $issuer_kind}
  keystores:
    pkcs12:
      create: true
      passwordSecretRef: {name: s11-web-keystore-pass, key: password}
EOF
kubectl -n "$ns" wait certificate s11-web --for=condition=Ready --timeout=5m >/dev/null

args=(s11 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml"
  --set ignition.secrets=null --set ignition.existingSecret=s11-gateway
  --set ignition.redundancy.enabled=true --set ignition.activeRouting.enabled=true
  --set ignition.ssl.enabled=true --set ignition.ssl.secretName=s11-web-tls
  --set "certManager.issuer.kind=$issuer_kind" --set "certManager.issuer.name=$issuer")
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")
e2e_render_check "${args[@]}"
log "installing redundant pair with activeRouting, web TLS and existingSecret"
e2e_install "${args[@]}"
e2e_wait_ready "$ns" 900
e2e_wait_pair "$ns" $STS 900
echo "  pair: $STS-0 $(e2e_gwinfo "$ns" $STS-0), $STS-1 $(e2e_gwinfo "$ns" $STS-1)" >> "$summary"

# activeRouting: the labeller polls every 2 s
for _ in $(seq 30); do e2e_active_check "$ns" $STS 2>/dev/null && break; sleep 2; done
e2e_active_check "$ns" $STS || die "active routing does not send traffic to the Master"
log "active routing: $STS-0 labelled and the only endpoint of $STS-active"

served=$(kubectl -n "$ns" exec $STS-0 -c gateway -- sh -c 'curl -skv --max-time 5 https://localhost:8043/StatusPing 2>&1' |
  grep -iE 'subject:|"state"' | tr -s ' ' | paste -sd' ' -)
grep -qE "CN ?= ?$CN" <<< "$served" || die "gateway does not serve the web certificate on 8043: $served"
log "web TLS: $served"

version=$(e2e_gwinfo "$ns" $STS-0 Version)
if [[ "$version" == 8.1.* ]]; then
  log "Ignition $version has no JDBC driver modules; skipped"
else
  for p in $STS-0 $STS-1; do
    kubectl -n "$ns" logs "$p" -c gateway > "$E2E_OUT/s11-$p.log" 2>&1 || true
    missing=$(e2e_modules_started "$E2E_OUT/s11-$p.log" "${JDBC_MODULES[@]}") ||
      die "$p (Ignition $version) did not start the JDBC driver modules: $missing"
  done
  log "Ignition $version: JDBC driver modules started on both gateways"
fi
echo "  active routing, web TLS and JDBC modules ok (Ignition $version)" >> "$summary"
e2e_watch_check

if [ -n "$UPGRADE_MODULE" ]; then
  modules=$(kubectl -n "$ns" get configmap $STS-config -o jsonpath='{.data.GATEWAY_MODULES_ENABLED}')
  case ",$modules," in *",$UPGRADE_MODULE,"*) die "$UPGRADE_MODULE is already enabled: $modules" ;; esac
  uids=$(kubectl -n "$ns" get pod $STS-0 $STS-1 -o jsonpath='{.items[*].metadata.uid}')
  log "upgrading with $UPGRADE_MODULE added to the modules"
  start=$(date +%s)
  # the chart's own default list (8.1 names; the chart translates them for 8.3)
  defaults=$(sed -n 's/^ *GATEWAY_MODULES_ENABLED: *"\(.*\)"$/\1/p' "$CHART/values.yaml")
  [ -n "$defaults" ] || die "no default GATEWAY_MODULES_ENABLED in $CHART/values.yaml"
  e2e_install "${args[@]}" --set "ignition.config.GATEWAY_MODULES_ENABLED=${defaults//,/\\,}\\,$UPGRADE_MODULE"
  deadline=$(( start + 1500 ))
  until e2e_rollout_done "$ns" $STS; do
    [ "$(date +%s)" -lt "$deadline" ] || { e2e_diagnose "$ns"; die "rolling update did not finish in $(( $(date +%s) - start ))s"; }
    sleep 5
  done
  log "rolling update finished in $(( $(date +%s) - start ))s"
  for u in $uids; do
    case " $(kubectl -n "$ns" get pod $STS-0 $STS-1 -o jsonpath='{.items[*].metadata.uid}') " in
      *" $u "*) die "pod $u was not replaced" ;;
    esac
  done
  t0=$(kubectl -n "$ns" get pod $STS-0 -o jsonpath='{.metadata.creationTimestamp}')
  t1=$(kubectl -n "$ns" get pod $STS-1 -o jsonpath='{.metadata.creationTimestamp}')
  [[ "$t1" < "$t0" ]] || die "Master (pod 0) was replaced before the Backup (pod 1)"
  e2e_wait_pair "$ns" $STS 900
  kubectl -n "$ns" logs $STS-1 -c gateway > "$E2E_OUT/s11-upgrade-$STS-1.log" 2>&1 || true
  incompatible=no
  ! grep -q '\[health-check\] Backup is Incompatible' "$E2E_OUT/s11-upgrade-$STS-1.log" || incompatible=yes
  log "module upgrade: Backup counted Ready while Incompatible: $incompatible"
  echo "  module upgrade (+$UPGRADE_MODULE): finished in $(( $(date +%s) - start ))s, Backup Incompatible on the way: $incompatible" >> "$summary"
  for _ in $(seq 30); do e2e_active_check "$ns" $STS 2>/dev/null && break; sleep 2; done
  e2e_active_check "$ns" $STS || die "active routing does not send traffic to the Master after the upgrade"
fi
e2e_watch_check
log "S11 passed"
