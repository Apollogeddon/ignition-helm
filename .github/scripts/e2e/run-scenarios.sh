#!/usr/bin/env bash
# Runs the test/e2e scenarios named in SCENARIOS against the current cluster and
# reports each result; S1 runs with and without activeRouting
# (s1-ingress-failover:active runs only the activeRouting mode).
set -uo pipefail

export HELM="${HELM:-helm}"
export E2E_OUT="${E2E_OUT:-$(pwd)/e2e-out}"
export NODE_IP="${NODE_IP:-$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')}"
export INGRESS_PORT="${INGRESS_PORT:-$(kubectl -n projectcontour get svc envoy \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')}"
mkdir -p "$E2E_OUT"
echo "NODE_IP=$NODE_IP INGRESS_PORT=$INGRESS_PORT"

results=()
run() {
  local name=$1; shift
  echo "::group::$name"
  if env "$@" bash "test/e2e/${name%%:*}.sh"; then results+=("PASS $name"); else results+=("FAIL $name"); fi
  echo "::endgroup::"
}

for s in ${SCENARIOS}; do
  case "$s" in
    s1-ingress-failover)
      run "$s" ACTIVE_ROUTING=false
      run "$s:active" ACTIVE_ROUTING=true ;;
    s1-ingress-failover:active) run "$s" ACTIVE_ROUTING=true ;;
    *) run "$s" ;;
  esac
done

printf '%s\n' "${results[@]}" | tee "$E2E_OUT/results.txt"
! grep -q '^FAIL' "$E2E_OUT/results.txt"
