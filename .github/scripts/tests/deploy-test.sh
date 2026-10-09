#!/usr/bin/env bash
# Deploys a chart to the kind cluster and checks what only shows on running
# gateways. The rendered objects (HPAs, PDBs, NetworkPolicies, volumes, probe
# commands, logger config) are covered by the helm-unittest suites instead.
#
#   1. A fresh install with charts/<chart>/ci/deploy-values.yaml: the gateways
#      reach RUNNING without restarting, the NetworkPolicy blocks another
#      namespace (and still lets the release's own namespace in), and the
#      chart options in the values file are in effect in the pod.
#   2. The chart from TARGET_BRANCH, installed and upgraded to this one with the
#      same values; skipped when the major version changes or the chart is new.
#
# Usage: deploy-test.sh <failover|scaleout>
# Env: TARGET_BRANCH (default main), CURL_IMAGE, TIMEOUT (helm --timeout, default 15m)
set -euo pipefail

chart=$1
dir="charts/$chart"
values="$dir/ci/deploy-values.yaml"
target="${TARGET_BRANCH:-main}"
curl_image="${CURL_IMAGE:-curlimages/curl:8.11.1}"
timeout="${TIMEOUT:-15m}"
ns=""

log() { echo "--- $*"; }

# die <message>: print what the cluster shows for the namespace under test, then fail
die() {
  echo "ERROR: $*"
  if [ -n "$ns" ]; then
    kubectl -n "$ns" get pods,events -o wide || true
    for pod in $(kubectl -n "$ns" get pods -o name 2>/dev/null); do
      kubectl -n "$ns" logs "$pod" --all-containers --tail=100 || true
    done
  fi
  exit 1
}

# begin <namespace> / end: one namespace per install, removed with its volumes
begin() { ns=$1; kubectl create namespace "$ns" >/dev/null; }
end() {
  helm uninstall "$chart" -n "$ns" --wait >/dev/null || true
  kubectl delete namespace "$ns" --wait=true >/dev/null
  ns=""
}

in_pod() { kubectl -n "$ns" exec "$1" -c gateway -- sh -c "$2"; }
spec() { kubectl -n "$ns" get pod "$1" -o jsonpath="$2"; }

check_running() {
  local status restarts
  status=$(in_pod "$1" 'curl -sf --max-time 5 http://localhost:8088/StatusPing') || die "$1 does not answer /StatusPing"
  [[ $status == *RUNNING* ]] || die "$1 is not RUNNING: $status"
  restarts=$(spec "$1" '{.status.containerStatuses[?(@.name=="gateway")].restartCount}')
  [ "$restarts" = 0 ] || die "$1 restarted $restarts times"
}

# curl_from <namespace> <pod name> <url>: succeeds when a one-off pod there gets a 2xx
curl_from() {
  kubectl run "$2" -n "$1" --image="$curl_image" --restart=Never --rm -i --quiet \
    --pod-running-timeout=3m --command -- curl -sf -o /dev/null --max-time 5 "$3"
}

# check_network_policy <service>: the same request must work from the release's
# namespace, so a failure from the other namespace can only be the policy
check_network_policy() {
  local url="http://$1.$ns.svc.cluster.local:8088/StatusPing" other="$ns-other"
  curl_from "$ns" "allowed-$1" "$url" || die "a pod in $ns cannot reach $1"
  kubectl create namespace "$other" >/dev/null
  if curl_from "$other" "denied-$1" "$url"; then
    kubectl delete namespace "$other" --wait=false >/dev/null
    die "a pod in another namespace reached $1 through the NetworkPolicy"
  fi
  kubectl delete namespace "$other" --wait=false >/dev/null
}

check_failover() {
  local pod=ignition-failover-0
  check_running "$pod"
  check_network_policy ignition-failover
  in_pod "$pod" 'test -s /usr/local/bin/ignition/temp/poststart-ran' || die "the postStart hook did not run"
  [ "$(spec "$pod" '{.spec.containers[0].readinessProbe.exec.command}')" = '["/config/scripts/health-check.sh","-t","4","-r"]' ] ||
    die "the readiness command from values is not used"
  [ -n "$(spec "$pod" '{.spec.containers[0].startupProbe.exec.command}')" ] || die "no startupProbe"
  in_pod "$pod" 'grep -q "<logger name=\"gateway.SslManager\" level=\"WARN\" />" /usr/local/bin/ignition/data/logback.xml' ||
    die "the logger level from values is not in logback.xml"
  in_pod "$pod" 'grep -q "<entryLimit>20000</entryLimit>" /usr/local/bin/ignition/data/logback.xml' ||
    die "the SQLite entryLimit from values is not in logback.xml"
  [ "$(spec "$pod" '{.spec.volumes[?(@.name=="ignition-failover-logs")].emptyDir.sizeLimit}')" = 256Mi ] ||
    die "the logs emptyDir has no size limit"
}

check_scaleout() {
  check_running ignition-scaleout-frontend-0
  check_running ignition-scaleout-backend-0
  in_pod ignition-scaleout-frontend-0 'curl -sf --max-time 5 http://ignition-scaleout-backend:8088/StatusPing' >/dev/null ||
    die "the frontend cannot reach the backend"
  check_network_policy ignition-scaleout-frontend
  check_network_policy ignition-scaleout-backend
}

major() { sed -n 's/^version: *"\{0,1\}\([0-9]*\)\..*/\1/p' "$1/Chart.yaml"; }

log "fresh install of $chart"
begin "deploy-$chart"
helm install "$chart" "$dir" -n "$ns" -f "$values" --wait --timeout "$timeout" || die "install failed"
"check_$chart"
end

log "upgrade of $chart from $target"
if ! git cat-file -e "origin/$target:$dir/Chart.yaml" 2>/dev/null; then
  log "skipped: $chart is not on $target"
  exit 0
fi
old=$(mktemp -d)
trap 'rm -rf "$old"' EXIT
git archive "origin/$target" charts | tar -x -C "$old"
if [ "$(major "$old/$dir")" != "$(major "$dir")" ]; then
  log "skipped: the major version changes, so the upgrade may need the manual steps in the README"
  exit 0
fi
helm dependency build "$old/$dir" >/dev/null
begin "deploy-$chart-upgrade"
helm install "$chart" "$old/$dir" -n "$ns" -f "$values" --wait --timeout "$timeout" || die "install of the $target chart failed"
helm upgrade "$chart" "$dir" -n "$ns" -f "$values" --wait --timeout "$timeout" || die "upgrade failed"
case "$chart" in
  failover) check_running ignition-failover-0 ;;
  scaleout) check_running ignition-scaleout-frontend-0; check_running ignition-scaleout-backend-0 ;;
esac
end
log "$chart passed"
