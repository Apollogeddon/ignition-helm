#!/usr/bin/env bash
# Runs the test/e2e scenarios named in SCENARIOS against the current cluster and
# reports each result; S01 runs with and without activeRouting
# (s01-ingress-failover:active runs only the activeRouting mode).
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
# run <name[:variant]> [VAR=value...]: run test/e2e/<name>.sh with the
# variables set; E2E_DRY_RUN=true only checks the script exists and that every
# argument is VAR=value (test/scripts/run-scenarios_test.sh uses this)
run() {
  local name=$1; shift
  if [ "${E2E_DRY_RUN:-}" = true ]; then
    local a ok=true
    [ -f "test/e2e/${name%%:*}.sh" ] || ok=false
    for a in "$@"; do [[ "$a" =~ ^[A-Z_][A-Z0-9_]*= ]] || ok=false; done
    if $ok; then results+=("PASS $name"); else results+=("FAIL $name"); fi
    echo "$name: $*"
    return
  fi
  echo "::group::$name"
  if env "$@" bash "test/e2e/${name%%:*}.sh"; then results+=("PASS $name"); else results+=("FAIL $name"); fi
  echo "::endgroup::"
}

for s in ${SCENARIOS}; do
  case "$s" in
    s01-ingress-failover)
      run "$s" ACTIVE_ROUTING=false
      run "$s:active" ACTIVE_ROUTING=true ;;
    s01-ingress-failover:active) run "$s" ACTIVE_ROUTING=true ;;
    s02-upgrade:active) run "$s" UPGRADE_SET=ignition.activeRouting.enabled=true ;;
    s02-upgrade:scaleout) run "$s" CHART_KIND=scaleout ;;
    # 3.1.0 installed by a wrapper chart with its own applicationName and
    # user 2003, then activeRouting
    s02-upgrade:wrapper) run "$s" FROM_VERSION=3.1.0 APP_NAME=my-gateway \
      "FROM_SET=ignition.securityContext.runAsUser=2003 ignition.securityContext.runAsGroup=2003 ignition.securityContext.fsGroup=2003" \
      UPGRADE_SET=ignition.activeRouting.enabled=true ;;
    # chart 3.1.0 with its default root user: the volume needs fixDataOwnership
    s02-upgrade:root) run "$s" FROM_VERSION=3.1.0 UPGRADE_SET=ignition.fixDataOwnership=true ;;
    *) run "$s" ;;
  esac
done

printf '%s\n' "${results[@]}" | tee "$E2E_OUT/results.txt"
! grep -q '^FAIL' "$E2E_OUT/results.txt"
