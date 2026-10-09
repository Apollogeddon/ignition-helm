#!/usr/bin/env bash
# S09: restore a gateway backup with `restore`. A source gateway gets a marker
# project and takes a backup (gwcmd -b); a second install restores it from a URL
# on its first start. Then the restored project is changed and the gateway
# restarted: the change must survive, as the backup is restored on the first
# start only, never again.
#
# Env: IMAGE_TAG (default chart appVersion), WATCH_URL (optional)
source "$(dirname "$0")/lib.sh"
CHART="$(dirname "$0")/../../charts/failover"
STS=ignition-failover
GW_DATA=/usr/local/bin/ignition/data
PROJECT=e2e_restore_marker

e2e_chart "$CHART"
e2e_begin "${WATCH_URL:-}"
ns=$(e2e_ns s09)
e2e_require_memory "$ns"

in_gw() { kubectl -n "$ns" exec $STS-0 -c gateway -- sh -c "$1"; }
# title: the marker project's title on the gateway, empty when it has none
title() {
  in_gw "cat $GW_DATA/projects/$PROJECT/project.json" 2>/dev/null |
    sed -n 's/.*"title": *"\([^"]*\)".*/\1/p' || true
}

args=(-n "$ns" -f "$(dirname "$0")/values/small.yaml")
[ -z "${IMAGE_TAG:-}" ] || args+=(--set "image.tag=$IMAGE_TAG")

# 1. the source gateway: a marker project, then a backup
e2e_render_check s09-source "$CHART" "${args[@]}"
log "installing the source gateway"
e2e_install s09-source "$CHART" "${args[@]}"
e2e_wait_ready "$ns" 900
in_gw "mkdir -p $GW_DATA/projects/$PROJECT && printf '%s\n' '{\"title\": \"restored-from-backup\", \"description\": \"\", \"parent\": null, \"enabled\": true, \"inheritable\": false}' > $GW_DATA/projects/$PROJECT/project.json"
log "taking a backup with gwcmd"
in_gw "cd /usr/local/bin/ignition && ./gwcmd.sh -b /usr/local/bin/ignition/temp/s09.gwbk" >&2 ||
  die "gwcmd could not take a backup"
kubectl -n "$ns" cp -c gateway "$STS-0:/usr/local/bin/ignition/temp/s09.gwbk" "$E2E_OUT/s09.gwbk" >/dev/null
[ -s "$E2E_OUT/s09.gwbk" ] || die "the backup is empty"
unzip -l "$E2E_OUT/s09.gwbk" | grep -q "$PROJECT" ||
  die "the backup does not contain $PROJECT, so a restore could not be told apart from a fresh gateway"
# the next install reuses the StatefulSet's name, so its volume must start empty:
# a leftover volume would hold the marker project without any restore
e2e_retry "$HELM" uninstall s09-source -n "$ns" --wait >/dev/null
kubectl -n "$ns" delete pvc --all --wait=true >/dev/null
[ -z "$(kubectl -n "$ns" get pvc -o name)" ] || die "the source gateway's volume is still there"

# 2. serve the backup inside the cluster
kubectl -n "$ns" apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: s09-files
  labels: {app: s09-files}
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile: {type: RuntimeDefault}
  containers:
  - name: httpd
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /tmp/www && exec httpd -f -p 8080 -h /tmp/www"]
    ports: [{containerPort: 8080}]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: {drop: [ALL]}
---
apiVersion: v1
kind: Service
metadata:
  name: s09-files
spec:
  selector: {app: s09-files}
  ports: [{port: 8080}]
EOF
kubectl -n "$ns" wait pod/s09-files --for=condition=Ready --timeout=3m >/dev/null
kubectl -n "$ns" cp "$E2E_OUT/s09.gwbk" s09-files:/tmp/www/backup.gwbk >/dev/null

# 3. a new install restores it on its first start
restore=(--set ignition.restore.enabled=true --set "ignition.restore.url=http://s09-files.$ns.svc.cluster.local:8080/backup.gwbk")
e2e_render_check s09 "$CHART" "${args[@]}" "${restore[@]}"
log "installing with restore"
e2e_install s09 "$CHART" "${args[@]}" "${restore[@]}"
e2e_wait_ready "$ns" 900
kubectl -n "$ns" logs $STS-0 -c preconfigure > "$E2E_OUT/s09-preconfigure-1.log" 2>&1 || true
[ "$(title)" = restored-from-backup ] || die "the gateway did not restore the backup (no $PROJECT project)"
log "backup restored"

# 4. a change after the restore survives a restart: the backup is not restored again
in_gw "sed -i 's/restored-from-backup/changed-after-restore/' $GW_DATA/projects/$PROJECT/project.json"
kubectl -n "$ns" delete pod $STS-0 --wait=true >/dev/null
e2e_wait_ready "$ns" 900
kubectl -n "$ns" logs $STS-0 -c preconfigure > "$E2E_OUT/s09-preconfigure-2.log" 2>&1 || true
grep -q "already staged" "$E2E_OUT/s09-preconfigure-2.log" || die "the backup was downloaded again on restart"
after=$(title)
[ "$after" = changed-after-restore ] || die "the restart restored the backup again (project title: ${after:-missing})"
restarts=$(kubectl -n "$ns" get pod $STS-0 -o jsonpath='{.status.containerStatuses[?(@.name=="gateway")].restartCount}')
[ "$restarts" = 0 ] || die "the gateway restarted $restarts times"

echo "S09 $(date -u +%FT%TZ) image=${IMAGE_TAG:-default}: restored, change kept across a restart" >> "$E2E_OUT/s09-summary.txt"
e2e_watch_check
log "S09 passed"
