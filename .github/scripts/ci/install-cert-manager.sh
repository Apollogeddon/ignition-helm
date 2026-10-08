#!/usr/bin/env bash
# Installs cert-manager, with a self-signed ClusterIssuer named cluster-issuer (the
# charts' default issuer), on the disposable kind cluster: the charts create
# cert-manager Certificates and Issuers by default, so they can't install without it.
set -euo pipefail

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.18.2}"

helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
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
