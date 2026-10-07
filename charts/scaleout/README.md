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
  --set frontend.redundancy.replicas=2
```

## Lifecycle Management Insights

* **SCADA Patch Pipeline:** Set `frontend.updateStrategy.type` or `backend.updateStrategy.type` to `OnDelete` to prevent automated Helm upgrades from unexpectedly terminating your running pods, allowing for strict, manual maintenance windows.
* **External Module Sideloading:** Define a PersistentVolumeClaim via `backend.externalModules.pvcName` (or frontend) to inject custom `.modl` plugins on startup.
* **Certificate rotation and renewal:** `certManager.rotation.enabled` adds CronJobs that refresh the Gateway Network keystore on each gateway's volume. A running gateway only loads renewed certificates when it restarts, so pair it with `certManager.restartOnRenewal.enabled`, which rolls the gateways (Backup first) when the certificate secrets change.

## Upgrading from 4.0.0 or earlier

From 4.1.0 the frontend and backend StatefulSets are governed by `<name>-frontend-headless` and `<name>-backend-headless`, and Kubernetes does not allow `serviceName` to change on an existing StatefulSet, so `helm upgrade` from 4.0.0 or earlier is rejected. Delete only the StatefulSet objects first; their pods and volumes keep running and the upgraded StatefulSets adopt them:

```sh
kubectl delete statefulset ignition-scaleout-frontend ignition-scaleout-backend --cascade=orphan -n <namespace>
helm upgrade <release> ignition-charts/ignition-scaleout -n <namespace> ...
```

(Tested end to end for the failover chart; the scaleout steps are the same.)

Turn on `backend.activeRouting.enabled` in a separate, later upgrade, once every pod has been replaced. Until the Master's pod is replaced it is only reachable under the old Service name, so the new Backup cannot sync with it; with `backend.activeRouting.enabled` a Backup must be in sync to be Ready, so the rollout would wait for ever (the Master keeps serving).

Charts up to 3.1.0 ran the gateway as root by default, so on storage that does not apply `fsGroup` (e.g. local-path) their data volumes are owned by root and the upgraded gateway, which runs as `securityContext.runAsUser` (2003), cannot update them: the `preconfigure` init container fails with `Permission denied`. If your 3.x install did not set `securityContext.runAsUser`, also set `frontend.fixDataOwnership` and `backend.fixDataOwnership=true` for the upgrade (an init container chowns the volume as root; it needs the baseline Pod Security level), and set it back to `false` once the pods are running.

## Configuration


| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `backend.secrets.GATEWAY_ADMIN_PASSWORD` | **Required.** Admin password for Backend gateways. | `admin` |
| `backend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for the Backend GAN keystore. | `metro` |
| `backend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for the Backend Web TLS keystore. | `ignition` |
| `frontend.secrets.GATEWAY_ADMIN_PASSWORD` | **Required.** Admin password for Frontend gateways. | `admin` |
| `frontend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for the Frontend GAN keystore. | `metro` |
| `frontend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for the Frontend Web TLS keystore. | `ignition` |
| `frontend.redundancy.replicas` | Number of Frontend nodes to deploy. | `1` |
| `backend.redundancy.enabled` | Enable Master/Backup redundancy for the Backend. | `false` |
| `backend.persistence.size` | Storage size for Backend nodes. | `3Gi` |
| `frontend.service.nodePorts` | Optional static NodePorts for Frontend. | unset |
| `backend.service.nodePorts` | Optional static NodePorts for Backend. | unset |
| `certManager.rotation.enabled` | CronJobs that refresh the Gateway Network keystore on each gateway's volume; renewed certificates load on the next restart (see `certManager.restartOnRenewal.enabled`). | `false` |
| `frontend.updateStrategy.type` | Helm patch rollout methodology for Frontend layer. | `RollingUpdate` |
| `backend.updateStrategy.type` | Helm patch rollout methodology for Backend layer. | `RollingUpdate` |
| `frontend.externalModules.enabled` | Enable mounting an isolated Persistent Volume Claim for modules. | `false` |
| `backend.externalModules.enabled` | Enable mounting an isolated Persistent Volume Claim for modules. | `false` |
| `backend.activeRouting.enabled` | Route user traffic only to the Active backend gateway of a redundant pair: a labeller keeps `redundancy-active=true` on the Active pod and the `<name>-backend-active` Service (which takes the configured service type, nodePorts and annotations) selects it. A Backup must also be in sync to be Ready. | `false` |
| `certManager.restartOnRenewal.enabled` | CronJob that starts a rolling restart (Backup first) when the Gateway Network or web certificate secrets change, so renewed certificates are loaded. | `false` |
| `frontend.logging.wrapperLogToStdout` | Append `wrapper.logfile=/dev/stdout` to `args` so the gateway log goes to the container log instead of an unrotated `logs/wrapper.log`. | `true` |
| `frontend.logging.loggers` | Per-logger levels, e.g. `{"gateway.SslManager": "DEBUG"}`. | `{}` |
| `frontend.logging.sqlite` | SQLite log database maintenance (`entryLimit`, `maxEventsPerMaintenance`, `minTimeBetweenMaintenance`, `vacuumFrequency`). | `{}` (Ignition defaults) |
| `frontend.readinessProbe` / `frontend.livenessProbe` | Probe settings. Readiness fails while the gateway is still commissioning. | `/config/scripts/health-check.sh -t 3 -r` / `-t 5` |
| `frontend.startupProbe.enabled` | Add a startupProbe so slow starts are tolerated while liveness stays strict. | `false` |
| `frontend.lifecycle` | Container lifecycle hooks, rendered as-is. | `{}` (none) |
| `frontend.emptyDirSizeLimit` | Optional `sizeLimit` for the `logs`, `temp` and `dotIgnition` emptyDir volumes. | unset |
| `frontend.ingress.className` | IngressClass name, e.g. `contour`; empty uses the cluster default. | `""` |
| `frontend.networkPolicy.extraIngress` | Extra NetworkPolicy ingress rules, e.g. the ingress controller namespace or node CIDRs. | `[]` |
| `frontend.fixDataOwnership` | Chown the data volume to the gateway user on start (an init container running as root). Only for upgrades from charts up to 3.1.0 installed with the default root user. | `false` |
| `backend.logging.wrapperLogToStdout` | Append `wrapper.logfile=/dev/stdout` to `args` so the gateway log goes to the container log instead of an unrotated `logs/wrapper.log`. | `true` |
| `backend.logging.loggers` | Per-logger levels, e.g. `{"gateway.SslManager": "DEBUG"}`. | `{}` |
| `backend.logging.sqlite` | SQLite log database maintenance (`entryLimit`, `maxEventsPerMaintenance`, `minTimeBetweenMaintenance`, `vacuumFrequency`). | `{}` (Ignition defaults) |
| `backend.readinessProbe` / `backend.livenessProbe` | Probe settings. Readiness fails while the gateway is still commissioning; with `backend.activeRouting` a Backup must also be in sync. | `/config/scripts/health-check.sh -t 3 -r` / `-t 5` |
| `backend.startupProbe.enabled` | Add a startupProbe so slow starts are tolerated while liveness stays strict. | `false` |
| `backend.lifecycle` | Container lifecycle hooks, rendered as-is. | `{}` (none) |
| `backend.emptyDirSizeLimit` | Optional `sizeLimit` for the `logs`, `temp` and `dotIgnition` emptyDir volumes. | unset |
| `backend.ingress.className` | IngressClass name, e.g. `contour`; empty uses the cluster default. | `""` |
| `backend.networkPolicy.extraIngress` | Extra NetworkPolicy ingress rules, e.g. the ingress controller namespace or node CIDRs. | `[]` |
| `backend.fixDataOwnership` | Chown the data volume to the gateway user on start (an init container running as root). Only for upgrades from charts up to 3.1.0 installed with the default root user. | `false` |
