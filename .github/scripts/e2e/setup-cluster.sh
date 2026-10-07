#!/usr/bin/env bash
# Installs what the e2e scenarios expect on the disposable kind cluster:
# cert-manager with a self-signed ClusterIssuer named cluster-issuer (the chart
# default), Contour as the ingress controller, and Chaos Mesh for S9.
set -euo pipefail

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.18.2}"
CONTOUR_VERSION="${CONTOUR_VERSION:-release-1.32}"
CHAOS_MESH_VERSION="${CHAOS_MESH_VERSION:-2.7.2}"

helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo add chaos-mesh https://charts.chaos-mesh.org --force-update >/dev/null

helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --version "$CERT_MANAGER_VERSION" --set crds.enabled=true --wait
kubectl apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cluster-issuer
spec:
  selfSigned: {}
YAML

kubectl apply -f "https://raw.githubusercontent.com/projectcontour/contour/${CONTOUR_VERSION}/examples/render/contour.yaml"
kubectl -n projectcontour rollout status deployment/contour --timeout=5m
kubectl -n projectcontour rollout status daemonset/envoy --timeout=5m

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace \
  --version "$CHAOS_MESH_VERSION" \
  --set chaosDaemon.runtime=containerd --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.create=false --wait

kubectl get nodes -o wide
