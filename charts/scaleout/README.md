# Ignition Scaleout Helm Chart

A Helm chart for deploying Inductive Automation Ignition in a **Scaleout** architecture. This chart separates the deployment into two distinct layers: **Frontend** (Perspective/Web) and **Backend** (Device/Database/Tag History).

## Features

* **Independent Scaling:** Scale Frontend nodes horizontally to handle thousands of concurrent Perspective sessions without impacting device communication.
* **Backend Redundancy:** The Backend layer supports standard Master/Backup redundancy for critical tag data and device connections.
* **Unified Gateway Network:** Automatically configures the Gateway Network so Frontend nodes can seamlessly proxy tags and queries from the Backend.

## Architecture

* **Backend:** A StatefulSet (Single or Redundant) that handles drivers, SQL databases, and tag execution.
* **Frontend:** A StatefulSet of stateless nodes that serve the UI and API traffic.

## Prerequisites

* Kubernetes 1.23+
* Helm 3.0+
* [cert-manager](https://cert-manager.io/docs/) installed and a `ClusterIssuer` configured (default: `cluster-issuer`)

## Installation

### Add Repository

```bash
helm repo add ignition-charts https://apollogeddon.github.io/ignition-helm
helm repo update
```

### Install Chart

To install the chart with the release name `my-scaleout`:

```bash
helm install my-scaleout ignition-charts/ignition-scaleout \
  --set backend.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword \
  --set frontend.replicas=2
```

## Configuration

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `backend.secrets.GATEWAY_ADMIN_PASSWORD` | **Required.** Admin password for Backend gateways. | `admin` |
| `backend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for the Backend GAN keystore. | `metro` |
| `backend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for the Backend Web TLS keystore. | `ignition` |
| `frontend.secrets.GATEWAY_ADMIN_PASSWORD` | **Required.** Admin password for Frontend gateways. | `admin` |
| `frontend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for the Frontend GAN keystore. | `metro` |
| `frontend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for the Frontend Web TLS keystore. | `ignition` |
| `frontend.replicas` | Number of Frontend nodes to deploy. | `1` |
| `backend.redundancy.enabled` | Enable Master/Backup redundancy for the Backend. | `true` |
| `backend.persistence.size` | Storage size for Backend nodes. | `3Gi` |
| `frontend.service.nodePorts` | Optional static NodePorts for Frontend. | `{}` |
| `backend.service.nodePorts` | Optional static NodePorts for Backend. | `{}` |
| `frontend.autoscaling.enabled` | (Future) Enable HPA for frontend nodes. | `false` |
