<br />
<div align="center">
  <a href="https://apollogeddon.github.io/ignition-helm">
    <img src="../docs/public/favicon.png" alt="Logo" width="100" height="100">
  </a>
  <h3 align="center">Ignition Helm Charts</h3>
  <p align="center">
    Deploy scalable, resilient Ignition architectures on Kubernetes with ease.
    <br />
    <a href="https://apollogeddon.github.io/ignition-helm"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/apollogeddon/ignition-helm/issues">Report Bug</a>
    ·
    <a href="https://github.com/apollogeddon/ignition-helm/issues">Request Feature</a>
  </p>
</div>

## 🚀 Overview

Enterprise-grade Helm charts for deploying Ignition Perspective on Kubernetes. Whether you need a simple redundant pair or a massive scaleout architecture, these charts provide a "batteries-included" experience with best practices built-in.

## ✨ Features

- **Failover Architecture**: Standard Master/Backup redundancy with automatic peering.
- **Scaleout Architecture**: Separate Frontend (Perspective/Vision) and Backend (Tags/History) workloads.
- **Automated Ops**: Self-configuring clusters using init containers to handle redundancy seeding and certificate exchange.
- **Security First**: Runs as non-root user, supports `SealedSecrets`, and manages certificates via `cert-manager`.
- **Battery Included**: Pre-configured probes, service accounts, and sensible defaults.

## 📦 Installation

Add the Helm repository:

```bash
helm repo add ignition-charts https://apollogeddon.github.io/ignition-helm
helm repo update
```

## 🛠️ Usage

### Failover (Master/Backup)

Deploy a standard redundant pair:

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.adminPassword=mysecretpassword
```

### Scaleout (Frontend/Backend)

Deploy a split architecture for high-scale environments:

```bash
helm install my-scaleout ignition-charts/ignition-scaleout \
  --set backend.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```
