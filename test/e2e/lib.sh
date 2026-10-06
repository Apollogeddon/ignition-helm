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
E2E_PROBE_IMAGE="${E2E_PROBE_IMAGE:-busybox:1.36}"
E2E_OUT="${E2E_OUT:-$(pwd)/e2e-out}"
HELM="${HELM:-helm}"
SNAPSHOT_KINDS="namespaces,customresourcedefinitions,clusterroles,clusterrolebindings,validatingwebhookconfigurations,mutatingwebhookconfigurations,ingressclasses,storageclasses,priorityclasses,persistentvolumes"

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }
die() { log "FAIL: $*"; exit 1; }

# e2e_snapshot <file>: cluster-scoped resources, excluding the e2e namespaces
# and the volumes bound to their claims, which teardown removes
e2e_snapshot() {
  kubectl get "$SNAPSHOT_KINDS" -o name | sort > "$1.all"
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

# e2e_ns <name>: create chart-e2e-<name> with the e2e label
e2e_ns() {
  local ns="chart-e2e-$1"
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

# e2e_require_memory <ns>: stop unless the node has E2E_MIN_FREE_MI available
e2e_require_memory() {
  local free
  free=$(e2e_free_mi "$1")
  log "node MemAvailable ${free}Mi (need ${E2E_MIN_FREE_MI}Mi)"
  [ "$free" -ge "$E2E_MIN_FREE_MI" ] || die "not enough free memory to start more gateways"
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
