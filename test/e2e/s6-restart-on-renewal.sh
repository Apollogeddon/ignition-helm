#!/usr/bin/env bash
# S6: certificate renewal is picked up by a rolling restart (restartOnRenewal),
# Backup first, with activeRouting keeping traffic on the Active gateway.
#   1. first certify run records the hash and restarts nothing
#   2. renewal (GAN TLS secret deleted, cert-manager re-issues it) -> the next
#      run restarts the StatefulSet: pod 1 (Backup) is replaced before pod 0
#   3. the pair is healthy again and a further run does nothing
# Availability through the -active NodePort is recorded throughout.
#
# Env: NODE_IP, WATCH_URL (optional), IMAGE_TAG (default chart appVersion)
source "$(dirname "$0")/lib.sh"
: "${NODE_IP:?}"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s6)
e2e_require_memory "$ns"

args=(s6 "$CHART" -n "$ns" -f "$(dirname "$0")/values/small.yaml"
  --set ignition.redundancy.enabled=true
  --set ignition.activeRouting.enabled=true
  --set certManager.restartOnRenewal.enabled=true)
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")
e2e_render_check "${args[@]}"
log "installing redundant pair with activeRouting and restartOnRenewal"
e2e_install "${args[@]}"
e2e_wait_ready "$ns" 900

gwinfo() { kubectl -n "$ns" exec "$1" -c gateway -- curl -s --max-time 3 http://localhost:8088/system/gwinfo 2>/dev/null |
  tr ';' '\n' | grep -E '^(RedundancyStatus|RedundantState|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -; }
wait_pair() {
  local deadline=$(( $(date +%s) + 900 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ "$(gwinfo $STS-0 || true)" = Master/Good/Active ] && [ "$(gwinfo $STS-1 || true)" = Backup/Good/Cold ] &&
      [ "$(kubectl -n "$ns" get pod $STS-0 -o jsonpath='{.metadata.labels.redundancy-active}' || true)" = true ]; then
      log "pair healthy"; return 0
    fi
    sleep 5
  done
  die "pair not healthy: $STS-0 $(gwinfo $STS-0 || true), $STS-1 $(gwinfo $STS-1 || true)"
}
# certify: run the CronJob now and print its log (called in $(...), so the job
# name comes from the clock rather than a counter)
certify() {
  local n
  n=$(date +%s)
  kubectl -n "$ns" create job "certify-$n" --from=cronjob/$STS-certify >/dev/null
  kubectl -n "$ns" wait job "certify-$n" --for=condition=complete --timeout=3m >/dev/null ||
    { kubectl -n "$ns" logs job/"certify-$n" >&2 || true; die "certify job $n failed"; }
  kubectl -n "$ns" logs job/"certify-$n"
}
uids() { kubectl -n "$ns" get pod $STS-0 $STS-1 -o jsonpath='{.items[*].metadata.uid}'; }

wait_pair
before=$(uids)
log "certify 1: $(certify)"
[ -n "$(kubectl -n "$ns" get sts $STS -o jsonpath='{.metadata.annotations.certify-hash}')" ] || die "no certify-hash recorded"
sleep 10
[ "$(uids)" = "$before" ] || die "first certify run restarted pods"

nodeport=$(kubectl -n "$ns" get svc $STS-active -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
"$(dirname "$0")/record.sh" 900 "$E2E_OUT/s6-restart.log" active="http://$NODE_IP:$nodeport/StatusPing" \
  via="http://$NODE_IP:$nodeport/system/gwinfo" &
rec=$!

log "renewing: deleting the GAN TLS secret so cert-manager re-issues it"
old=$(kubectl -n "$ns" get secret $STS-gan-tls -o jsonpath='{.data.tls\.crt}')
kubectl -n "$ns" delete secret $STS-gan-tls >/dev/null
for _ in $(seq 60); do
  new=$(kubectl -n "$ns" get secret $STS-gan-tls -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
  [ -n "$new" ] && [ "$new" != "$old" ] && break
  sleep 2
done
[ -n "$new" ] && [ "$new" != "$old" ] || die "certificate was not re-issued"
log "certificate re-issued"

log "certify 2: $(certify)"
start=$(date +%s)
# wait for both pods to be replaced and the pair to recover
for _ in $(seq 180); do
  [ "$(kubectl -n "$ns" get sts $STS -o jsonpath='{.status.updatedReplicas}/{.status.readyReplicas}')" = 2/2 ] &&
    [ "$(kubectl -n "$ns" get sts $STS -o jsonpath='{.status.currentRevision}')" = "$(kubectl -n "$ns" get sts $STS -o jsonpath='{.status.updateRevision}')" ] && break
  sleep 5
done
wait_pair
log "rolling restart finished in $(( $(date +%s) - start ))s"
kill "$rec" 2>/dev/null; wait "$rec" 2>/dev/null || true

t0=$(kubectl -n "$ns" get pod $STS-0 -o jsonpath='{.metadata.creationTimestamp}')
t1=$(kubectl -n "$ns" get pod $STS-1 -o jsonpath='{.metadata.creationTimestamp}')
log "pod creation: $STS-1 $t1, $STS-0 $t0"
for u in $before; do case " $(uids) " in *" $u "*) die "pod $u was not replaced" ;; esac; done
[[ "$t1" < "$t0" ]] || die "Master (pod 0) was replaced before the Backup (pod 1)"

log "certify 3: $(certify)"
after=$(uids); sleep 10
[ "$(uids)" = "$after" ] || die "certify run after the restart restarted pods again"

awk '{split($3, v, "="); s = (v[2] ~ /\/Active$/) ? "served" : "not-served"; c[s]++}
  END {for (k in c) printf "  %s %ds\n", k, c[k]}' "$E2E_OUT/s6-restart.log" | tee -a "$E2E_OUT/s6-summary.txt" >&2
awk '{print $1, $3}' "$E2E_OUT/s6-restart.log" | awk '{s=$2} s!=p {print; p=s}' > "$E2E_OUT/s6-transitions.txt"
e2e_watch_check
log "S6 passed"
