---
title: Installation
description: How to install the Ignition Helm Charts.
---

## Tools & Dependencies

Before installing the charts, you will need a few tools installed on your machine.

### Windows (via winget)

If you are on Windows, you can use `winget` to install the required dependencies.

```powershell
# Install Kubernetes CLI (kubectl)
winget install Kubernetes.kubectl

# Install Helm (Package Manager)
winget install Helm.Helm
```

### Verification

Ensure the tools are installed correctly by checking their versions:

```bash
kubectl version --client
helm version
```

## Cluster Setup

### 1. Kubernetes Cluster

You will need a running Kubernetes cluster (Version 1.23+). If you don't have one, **Docker Desktop** (with Kubernetes enabled) or **Kind** are great options for local development.

### 2. Cert-Manager

These charts rely on `cert-manager` for automatic SSL certificate generation (specifically for the Gateway Network). Install it directly from the official manifest:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
```

Wait for the pods to be ready in the `cert-manager` namespace:

```bash
kubectl get pods -n cert-manager
```

### 3. Cluster Issuer

The charts default to looking for a `ClusterIssuer` named `cluster-issuer`. For local development or internal networks, a **Self-Signed** issuer is the easiest way to get started.

Create a file named `issuer.yaml` with the following content:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cluster-issuer
spec:
  selfSigned: {}
```

Apply it to your cluster:

```bash
kubectl apply -f issuer.yaml
```

## Installing the Charts

### Adding the Repository

Add the Helm repository to your local client:

```bash
helm repo add ignition-charts https://apollogeddon.github.io/ignition-helm
helm repo update
```

### Installation Options

#### Failover (Standard Redundancy)

This deploys a standard Master/Backup pair.

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.adminPassword=mysecretpassword
```

#### Scaleout (Frontend/Backend)

This deploys separate Frontend and Backend clusters.

```bash
helm install my-scaleout ignition-charts/ignition-scaleout \
  --set backend.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```
