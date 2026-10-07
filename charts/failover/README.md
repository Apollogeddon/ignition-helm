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

## Lifecycle Management Insights

* **SCADA Patch Pipeline:** Set `ignition.updateStrategy.type` to `OnDelete` to prevent automated Helm upgrades from unexpectedly terminating your running pods, allowing for strict, manual maintenance windows.
* **External Module Sideloading:** Define a PersistentVolumeClaim via `ignition.externalModules.pvcName` to inject your custom `.modl` plugins on container startup, eliminating the need to maintain custom docker images.
* **Health Checks and Shutdown:** Probes check `/StatusPing` for `RUNNING`, which works on Ignition 8.1 and 8.3. Readiness (`health-check.sh -r`) also fails while the gateway is still commissioning; liveness does not, so a gateway stuck commissioning is not restarted in a loop. There is no default `preStop` hook: on SIGTERM the gateway shuts down gracefully, and `gwcmd.sh -p` (previously used here) resets the gateway login password.
* **Zero-Downtime Cert Rotation:** Enable `certManager.rotation.enabled` to spin up smart Kubernetes CronJobs that securely rotate the Ignition instances' PKI trust fabric under-the-hood before certificate expiration.

## Upgrading from 4.1.0

Pods created by chart 4.1.0 run `/config/scripts/shutdown.sh` as their preStop hook, and in 4.1.0 that script calls `gwcmd.sh -p`, which resets the gateway login. This chart ships `shutdown.sh` as a no-op, but running pods only see it once the scripts Secret has refreshed in their volume, so upgrade in two steps:

1. `helm upgrade ... --set ignition.updateStrategy.type=OnDelete` (only the Secret changes; no pod restarts)
2. Wait until each pod's `/config/scripts/shutdown.sh` no longer calls `gwcmd` (usually 1-2 minutes)
3. `helm upgrade ...` again with the default `RollingUpdate`; the Backup is replaced first


## Configuration


The following table lists the configurable parameters of the chart and their default values. For a comprehensive list, consult the `values.yaml` file.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `ignition.secrets.GATEWAY_ADMIN_PASSWORD` | **Required.** Password for the `admin` user. | `admin` |
| `ignition.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for the Gateway Network keystore. | `metro` |
| `ignition.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for the Web Server TLS keystore. | `ignition` |
| `ignition.redundancy.enabled` | Enable Master/Backup redundancy (2 replicas). | `false` |
| `ignition.image.tag` | Ignition version to deploy. | `8.3` |
| `ignition.resources` | CPU/Memory requests and limits. | `Requests: 500m/1Gi` |
| `ignition.persistence.size` | Size of the persistent volume claim. | `3Gi` |
| `ignition.service.type` | Kubernetes Service type (NodePort, LoadBalancer, etc). | `NodePort` |
| `ignition.service.nodePorts` | Optional static NodePorts (http, https, gan). | `{}` |
| `ignition.activeRouting.enabled` | Route user traffic only to the Active gateway of a redundant pair: a labeller keeps `redundancy-active=true` on the Active pod, the `<name>-active` Service (which takes the configured service type, nodePorts and annotations) selects it, and the Ingress points at it. Readiness also requires a Backup to be in sync. | `false` |
| `certManager.restartOnRenewal.enabled` | CronJob that starts a rolling restart (Backup first) when the GAN or web certificate secrets change, so renewed certificates are loaded. | `false` |
| `ignition.ingress.enabled` | Enable Ingress resource generation. | `false` |
| `ignition.ingress.className` | IngressClass name, e.g. `contour`; empty uses the cluster default. | `""` |
| `certManager.issuer.name` | Name of the Cert-Manager Issuer to use. | `cluster-issuer` |
| `certManager.rotation.enabled` | Deploy CronJobs to auto-rotate GAN certificates without manual restart. | `false` |
| `ignition.updateStrategy.type` | Helm patch rollout methodology (`RollingUpdate` or `OnDelete`). | `RollingUpdate` |
| `ignition.externalModules.enabled` | Enable mounting an isolated Persistent Volume Claim for modules. | `false` |
| `ignition.readinessProbe` / `ignition.livenessProbe` | Probe settings. A configured `command` is used as-is; the chart health check (`/StatusPing` must report `RUNNING`) is the fallback when it is empty. | image `health-check.sh -t 3` / `-t 5` |
| `ignition.startupProbe.enabled` | Add a startupProbe so slow starts are tolerated while liveness stays strict. | `false` |
| `ignition.lifecycle` | Container lifecycle hooks, rendered as-is. | `{}` (none) |
| `ignition.logging.loggers` | Per-logger levels, e.g. `{"gateway.SslManager": "DEBUG"}`. | `{}` |
| `ignition.logging.wrapperLogToStdout` | Append `wrapper.logfile=/dev/stdout` to `args` so the gateway log goes to the container log instead of an unrotated `logs/wrapper.log`. Skipped when `args` already set `wrapper.logfile`. | `true` |
| `ignition.logging.sqlite` | SQLite log database maintenance (`entryLimit`, `maxEventsPerMaintenance`, `minTimeBetweenMaintenance`, `vacuumFrequency`). | `{}` (Ignition defaults) |
| `ignition.emptyDirSizeLimit` | Optional `sizeLimit` for the `logs`, `temp` and `dotIgnition` emptyDir volumes. | unset |
| `ignition.networkPolicy.extraIngress` | Extra NetworkPolicy ingress rules, e.g. the ingress controller namespace or node CIDRs. | `[]` |
