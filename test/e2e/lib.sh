#!/usr/bin/env bash
# Guardrails for running chart e2e scenarios on a shared cluster.
# Source this file; see test/e2e/README.md.
#
# Everything a scenario creates lives in namespaces labelled e2e=ignition-helm,
# nothing cluster-scoped is created, and teardown is verified against a
# snapshot of cluster-scoped resources taken before the run.

set -euo pipefail

E2E_LABEL="e2e=ignition-helm"
E2E_MIN_FREE_MI="${E2E_MIN_FREE_MI:-4096}"
E2E_MIN_REQUEST_MI="${E2E_MIN_REQUEST_MI:-1024}"
E2E_PROBE_IMAGE="${E2E_PROBE_IMAGE:-busybox:1.36}"
E2E_OUT="${E2E_OUT:-$(pwd)/e2e-out}"
HELM="${HELM:-helm}"
SNAPSHOT_KINDS="namespaces,customresourcedefinitions,clusterroles,clusterrolebindings,validatingwebhookconfigurations,mutatingwebhookconfigurations,ingressclasses,storageclasses,priorityclasses,persistentvolumes"

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }
die() { log "FAIL: $*"; exit 1; }

# Clusters reached through a proxy (e.g. the GitLab agent) drop API connections
# now and then. kubectl and helm calls are retried on connection errors only;
# any other error is returned at once.
E2E_CONN_ERRORS='unable to connect|connection attempt failed|i/o timeout|connection reset|unexpected EOF|TLS handshake|connection refused|wsarecv|wsasend'
e2e_retry() {
  local i rc err
  err=$(mktemp)
  for i in 1 2 3 4 5; do
    if "$@" 2>"$err"; then rc=0; else rc=$?; fi
    if [ "$rc" -ne 0 ] && grep -qiE "$E2E_CONN_ERRORS" "$err"; then
      log "API connection dropped, retrying ($i/5): $1 ${2:-}"
      sleep 5
      continue
    fi
    cat "$err" >&2; rm -f "$err"
    return "$rc"
  done
  cat "$err" >&2; rm -f "$err"
  return 1
}
kubectl() { e2e_retry command kubectl "$@"; }

# e2e_install <helm args...>: helm upgrade --install (safe to retry), without
# --wait, which fails outright when the API connection drops; use e2e_wait_ready
e2e_install() {
  e2e_retry "$HELM" upgrade --install "$@" >/dev/null
}

# e2e_wait_ready <ns> <timeout seconds>: wait until every StatefulSet and
# Deployment in the namespace has all its replicas Ready
e2e_wait_ready() {
  local deadline=$(( $(date +%s) + $2 )) s
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if s=$(kubectl -n "$1" get statefulsets,deployments -o jsonpath='{range .items[*]}{.spec.replicas}/{.status.readyReplicas}{"\n"}{end}') &&
      [ -n "$s" ] && awk -F/ '$1 != $2 {bad = 1} END {exit bad}' <<< "$s"; then
      return 0
    fi
    sleep 5
  done
  e2e_diagnose "$1"
  die "workloads in $1 not Ready after $2s (see $E2E_OUT/diag-$1.txt)"
}

# e2e_diagnose <ns>: save pod status, events, health and recent logs before
# teardown removes the namespace
e2e_diagnose() {
  local out="$E2E_OUT/diag-$1.txt" p
  {
    echo "== pods"; kubectl -n "$1" get pods -o wide
    echo "== events"; kubectl -n "$1" get events --sort-by=.lastTimestamp
    for p in $(kubectl -n "$1" get pods -o jsonpath='{.items[*].metadata.name}'); do
      echo "== $p StatusPing / gwinfo"
      kubectl -n "$1" exec "$p" -- sh -c 'curl -s --max-time 3 http://localhost:8088/StatusPing; echo;
        curl -s --max-time 3 http://localhost:8088/system/gwinfo | tr ";" "\n" | grep -E "ContextStatus|Redundan"'
      echo "== $p logs (last 60)"; kubectl -n "$1" logs "$p" --all-containers --tail=60
    done
  } > "$out" 2>&1 || true
  log "diagnostics saved to $out"
}

# e2e_snapshot <file>: cluster-scoped resources, excluding the e2e namespaces
# and the volumes bound to their claims, which teardown removes
e2e_snapshot() {
  # an empty or partial listing would read as "everything removed", so retry
  # until it at least contains kube-system
  local i
  for i in 1 2 3 4 5; do
    kubectl get "$SNAPSHOT_KINDS" -o name 2>/dev/null | sort > "$1.all" || true
    grep -qx 'namespace/kube-system' "$1.all" && break
    [ "$i" -lt 5 ] || die "could not list cluster-scoped resources"
    sleep 5
  done
  { kubectl get ns -l "$E2E_LABEL" -o name
    kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name} {.spec.claimRef.namespace}{"\n"}{end}' |
      awk '$2 ~ /^chart-e2e-/ {print "persistentvolume/" $1}'
  } | sort > "$1.e2e"
  comm -23 "$1.all" "$1.e2e" > "$1"
  rm -f "$1.all" "$1.e2e"
}

# e2e_render_check <helm template args...>: refuse charts that render
# cluster-scoped objects
e2e_render_check() {
  local cluster_kinds kinds bad=""
  cluster_kinds=$(kubectl api-resources --namespaced=false --no-headers | awk '{print $NF}')
  kinds=$("$HELM" template "$@" | awk '/^kind:/ {print $2}' | sort -u)
  for k in $kinds; do
    grep -qx "$k" <<< "$cluster_kinds" && bad="$bad $k"
  done
  [ -z "$bad" ] || die "chart renders cluster-scoped kinds:$bad"
}

# e2e_chart <chart dir>: build the chart dependencies so the working-tree
# common library is what gets rendered
e2e_chart() {
  "$HELM" dependency build "$1" >/dev/null
}

# e2e_ns <name>: create chart-e2e-<name> with the e2e label
e2e_ns() {
  local ns="chart-e2e-$1" i
  # a namespace from an earlier run may still be terminating
  for i in $(seq 120); do
    kubectl get namespace "$ns" >/dev/null 2>&1 || break
    [ "$i" -lt 120 ] || die "namespace $ns from an earlier run is still there"
    sleep 5
  done
  kubectl create namespace "$ns" >/dev/null
  kubectl label namespace "$ns" "$E2E_LABEL" >/dev/null
  echo "$ns"
}

# e2e_free_mi <ns>: MemAvailable of the node, read from a short-lived pod
e2e_free_mi() {
  local kb
  kb=$(kubectl -n "$1" run "e2e-meminfo-$RANDOM" --image="$E2E_PROBE_IMAGE" --restart=Never --rm -i --quiet \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"m","image":"'"$E2E_PROBE_IMAGE"'","command":["awk","/^MemAvailable:/ {print $2}","/proc/meminfo"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
    2>/dev/null | tr -dc '0-9')
  [ -n "$kb" ] || die "could not read MemAvailable"
  echo $(( kb / 1024 ))
}

# e2e_request_headroom_mi: the most memory any node can still promise to new
# pods (allocatable minus the requests of its running pods)
e2e_request_headroom_mi() {
  local node alloc used best=0
  for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    alloc=$(kubectl get node "$node" -o jsonpath='{.status.allocatable.memory}' | e2e_to_mi)
    used=$(kubectl get pods -A --field-selector "spec.nodeName=$node,status.phase!=Succeeded,status.phase!=Failed" \
      -o jsonpath='{range .items[*].spec.containers[*]}{.resources.requests.memory}{"\n"}{end}' | e2e_to_mi)
    [ $(( alloc - used )) -le "$best" ] || best=$(( alloc - used ))
  done
  echo "$best"
}
# e2e_to_mi: sum Kubernetes memory quantities (one per line) in MiB
e2e_to_mi() {
  awk '/^[0-9]/ {
    n = $0 + 0; u = $0; sub(/^[0-9.]+/, "", u)
    f = (u == "Ki") ? 1/1024 : (u == "Mi") ? 1 : (u == "Gi") ? 1024 : (u == "Ti") ? 1048576 :
        (u == "k") ? 1000/1048576 : (u == "M") ? 1e6/1048576 : (u == "G") ? 1e9/1048576 : 1/1048576
    t += n * f
  } END {printf "%d\n", t}'
}

# e2e_require_memory <ns>: stop unless the node has E2E_MIN_FREE_MI available
# and some node can still schedule E2E_MIN_REQUEST_MI of requests, so a test
# never competes with other workloads' rollouts for the last of the capacity
e2e_require_memory() {
  local free headroom
  free=$(e2e_free_mi "$1")
  headroom=$(e2e_request_headroom_mi)
  log "node MemAvailable ${free}Mi (need ${E2E_MIN_FREE_MI}Mi), request headroom ${headroom}Mi (need ${E2E_MIN_REQUEST_MI}Mi)"
  [ "$free" -ge "$E2E_MIN_FREE_MI" ] || die "not enough free memory to start more gateways"
  [ "$headroom" -ge "$E2E_MIN_REQUEST_MI" ] || die "not enough unrequested memory to schedule more gateways"
}

# e2e_watch_start <url>: poll a URL once a second in the background; failures
# are appended to $E2E_OUT/watch.failures
e2e_watch_start() {
  mkdir -p "$E2E_OUT"
  : > "$E2E_OUT/watch.failures"
  ( while :; do
      code=$(curl -sk --max-time 2 -o /dev/null -w '%{http_code}' "$1" || true)
      case "$code" in 2??|3??) ;; *) echo "$(date -u +%H:%M:%S) $code" >> "$E2E_OUT/watch.failures" ;; esac
      sleep 1
    done ) &
  E2E_WATCH_PID=$!
  log "watching $1 (pid $E2E_WATCH_PID)"
}

# e2e_watch_check: stop the run if the watched URL has failed
e2e_watch_check() {
  [ -n "${E2E_WATCH_PID:-}" ] || return 0
  [ ! -s "$E2E_OUT/watch.failures" ] || die "watched URL failed: $(tail -1 "$E2E_OUT/watch.failures")"
}

e2e_watch_stop() {
  [ -n "${E2E_WATCH_PID:-}" ] || return 0
  kill "$E2E_WATCH_PID" 2>/dev/null || true
  wait "$E2E_WATCH_PID" 2>/dev/null || true
  E2E_WATCH_PID=""
}

# e2e_teardown: delete every e2e namespace and wait until they are gone
e2e_teardown() {
  e2e_watch_stop
  log "deleting namespaces labelled $E2E_LABEL"
  kubectl delete ns -l "$E2E_LABEL" --wait=true --timeout=10m >/dev/null || true
}

# e2e_verify <before>: compare cluster-scoped resources with the snapshot
e2e_verify() {
  local after="$1.after"
  e2e_snapshot "$after"
  if diff "$1" "$after" > "$1.diff"; then
    log "cluster-scoped resources unchanged"
  else
    cat "$1.diff" >&2
    die "cluster-scoped resources changed"
  fi
}

# e2e_begin <url-to-watch>: snapshot, start the watch, register teardown
e2e_begin() {
  mkdir -p "$E2E_OUT"
  e2e_snapshot "$E2E_OUT/before.txt"
  log "snapshot: $(wc -l < "$E2E_OUT/before.txt") cluster-scoped resources"
  [ -z "${1:-}" ] || e2e_watch_start "$1"
  trap 'rc=$?; e2e_teardown; e2e_verify "$E2E_OUT/before.txt"; exit $rc' EXIT
}
