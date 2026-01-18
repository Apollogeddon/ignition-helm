# Ignition Failover Helm Chart

A Helm chart for deploying Inductive Automation Ignition in a **Failover** architecture on Kubernetes. This chart deploys a StatefulSet capable of standard Master/Backup redundancy.

## Features

* **Standard Redundancy:** Deploys two nodes (Master and Backup) with automatic failover.
* **Automated Peering:** Uses init containers and the Kubernetes API to automatically configure the Gateway Network between nodes.
* **Certificate Management:** Integrates with `cert-manager` to automatically generate and trust Gateway Network (GAN) certificates.
* **State Persistence:** StatefulSet architecture ensures stable network identities and persistent storage for each node.

## Prerequisites

* Kubernetes 1.23+
* Helm 3.0+
* PV provisioner support in the underlying infrastructure
* [cert-manager](https://cert-manager.io/docs/) installed and a `ClusterIssuer` configured (default: `cluster-issuer`)

## Installation

### Add Repository

```bash
helm repo add ignition-charts https://apollogeddon.github.io/ignition-helm
helm repo update
```

### Install Chart

To install the chart with the release name `my-ignition`:

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```

### Enable Redundancy

By default, the chart deploys a single node (Standalone). To enable redundancy:

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.redundancy.enabled=true \
  --set ignition.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```

## Configuration

The following table lists the configurable parameters of the chart and their default values. For a comprehensive list, consult the `values.yaml` file.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `ignition.secrets.GATEWAY_ADMIN_PASSWORD` | **Required.** Password for the `admin` user. | `admin` |
| `ignition.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for the Gateway Network keystore. | `metro` |
| `ignition.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for the Web Server TLS keystore. | `ignition` |
| `ignition.redundancy.enabled` | Enable Master/Backup redundancy (2 replicas). | `true` |
| `ignition.image.tag` | Ignition version to deploy. | `8.3` |
| `ignition.resources` | CPU/Memory requests and limits. | `Requests: 500m/1Gi` |
| `ignition.persistence.size` | Size of the persistent volume claim. | `3Gi` |
| `ignition.service.type` | Kubernetes Service type (NodePort, LoadBalancer, etc). | `NodePort` |
| `ignition.service.nodePorts` | Optional static NodePorts (http, https, gan). | `{}` |
| `ignition.ingress.enabled` | Enable Ingress resource generation. | `false` |
| `certManager.issuer.name` | Name of the Cert-Manager Issuer to use. | `cluster-issuer` |
