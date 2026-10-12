#!/usr/bin/env bash
# Renders every values file in examples/ with its chart, and checks that a
# layer the example exposes beyond its namespace (a LoadBalancer, an Ingress,
# a ServiceMonitor, or a NodePort the example asks for) has a NetworkPolicy
# rule letting that traffic in, as the default policy admits only pods in the
# namespace. The charts' own default NodePort Service is left out: it serves
# in-cluster clients under the default policy, as the docs say.
# Usage: test/scripts/examples_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fails=0
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
# docs <path regex>: the rendered documents from templates matching the regex
docs() { awk -v s="$1" '/^# Source: / {on = ($3 ~ s)} on' "$work/out.yaml"; }

count=0
while IFS= read -r example; do
  count=$((count + 1))
  name="${example#"$root"/}"
  case "$name" in
    examples/scaleout/*) chart=scaleout; layers="templates/frontend/ templates/backend/" ;;
    *) chart=failover; layers="templates/" ;;
  esac
  if ! "$HELM" template ex "$root/charts/$chart" -f "$example" > "$work/out.yaml" 2> "$work/err"; then
    fail "$name does not render with the $chart chart"; sed 's/^/     /' "$work/err"; continue
  fi
  bad=0
  for layer in $layers; do
    exposed=""
    docs "/${layer}[^/]*service[.]yaml$" | grep -q "type: LoadBalancer" && exposed="a LoadBalancer"
    docs "/${layer}[^/]*service[.]yaml$" | grep -q "type: NodePort" &&
      grep -q "type: NodePort" "$example" && exposed="a NodePort"
    docs "/${layer}[^/]*ingress[.]yaml$" | grep -q "^kind: Ingress" && exposed="an Ingress"
    docs "/${layer}servicemonitor[.]yaml$" | grep -q "^kind: ServiceMonitor" && exposed="a ServiceMonitor"
    [ -n "$exposed" ] || continue
    policy=$(docs "/${layer}networkpolicy[.]yaml$")
    [ -n "$policy" ] || continue
    if ! printf '%s\n' "$policy" | grep -qE "namespaceSelector:|ipBlock:"; then
      fail "$name: ${layer} has ${exposed}, but its NetworkPolicy admits only pods in the namespace"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ] && echo "ok   $name"
done < <(find "$root/examples" -name '*.yaml' | sort)

[ "$count" -gt 0 ] || fail "no examples found"
if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
