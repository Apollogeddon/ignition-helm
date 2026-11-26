#!/usr/bin/env bash
# Installs what the e2e scenarios expect on the disposable kind cluster:
# cert-manager with a self-signed ClusterIssuer named cluster-issuer (the chart
# default) and a CA-type ClusterIssuer named e2e-ca-issuer (S11), Contour as the
# ingress controller, and Chaos Mesh for S10.
set -euo pipefail

CONTOUR_VERSION="${CONTOUR_VERSION:-release-1.32}"
CHAOS_MESH_VERSION="${CHAOS_MESH_VERSION:-2.7.2}"

helm repo add chaos-mesh https://charts.chaos-mesh.org --force-update >/dev/null

"$(dirname "$0")/../ci/install-cert-manager.sh"

# a CA ClusterIssuer, as many clusters use: its CA is issued by cluster-issuer,
# into cert-manager's own namespace, where a ClusterIssuer reads its secret
kubectl apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: e2e-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: e2e-ca
  secretName: e2e-ca
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {name: cluster-issuer, kind: ClusterIssuer}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: e2e-ca-issuer
spec:
  ca:
    secretName: e2e-ca
YAML
kubectl -n cert-manager wait certificate e2e-ca --for=condition=Ready --timeout=5m
kubectl wait clusterissuer e2e-ca-issuer --for=condition=Ready --timeout=5m

kubectl apply -f "https://raw.githubusercontent.com/projectcontour/contour/${CONTOUR_VERSION}/examples/render/contour.yaml"
kubectl -n projectcontour rollout status deployment/contour --timeout=5m
kubectl -n projectcontour rollout status daemonset/envoy --timeout=5m

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh --create-namespace \
  --version "$CHAOS_MESH_VERSION" \
  --set chaosDaemon.runtime=containerd --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.create=false --wait

kubectl get nodes -o wide
