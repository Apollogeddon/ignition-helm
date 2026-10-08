# Ignition scaleout Helm chart

`ignition-scaleout` deploys Inductive Automation's Ignition on Kubernetes in a scaleout architecture: backend gateways that run devices, databases and tag history, and frontend gateways that serve Perspective sessions and connect to the backend over the Gateway Network. Use it when user load needs to scale separately from device communication. For a single gateway or one redundant pair, see [`ignition-failover`](../failover/README.md).

## Features

- **Independent scaling**: scale the frontend gateways, manually or with a HorizontalPodAutoscaler, without touching the backend.
- **Backend redundancy**: the backend can run as a Master/Backup pair with `backend.redundancy.enabled`.
- **Gateway Network setup**: cert-manager issues each layer's Gateway Network certificates from a CA the chart creates, and the frontends are configured to connect to the backend gateways.

## Architecture

- **Backend**: a StatefulSet of one gateway, or a redundant pair, with a persistent volume per gateway. Its EAM role is `Controller`.
- **Frontend**: a StatefulSet of `frontend.redundancy.replicas` gateways without persistent volumes. Its EAM role is `Agent`.

## Prerequisites

- Kubernetes 1.23 or later, with a storage class that can provision persistent volumes.
- Helm 3. The CI workflows use Helm v3.22.0.
- [cert-manager](https://cert-manager.io/docs/installation/) and an issuer that can sign a CA certificate, by default a `ClusterIssuer` named `cluster-issuer` (set `certManager.issuer.name` and `certManager.issuer.kind` to use another). A self-signed `ClusterIssuer` is enough:

  ```yaml
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: cluster-issuer
  spec:
    selfSigned: {}
  ```

## Installation

Add the Helm repository:

```bash
helm repo add ignition-charts https://apollogeddon.github.io/ignition-helm
helm repo update
```

Install the chart with the release name `my-scaleout` and two frontend gateways:

```bash
helm install my-scaleout ignition-charts/ignition-scaleout \
  --set backend.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword \
  --set frontend.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword \
  --set frontend.redundancy.replicas=2
```

Resources are named after `applicationName` (default `ignition-scaleout`), not the release name: the StatefulSets are `ignition-scaleout-frontend` and `ignition-scaleout-backend`.

Both layers' Gateway Network keystores are created with `frontend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD`, so if you change it, set `backend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` to the same value.

## Operations

- **Controlled rollouts**: set `frontend.updateStrategy.type` or `backend.updateStrategy.type` to `OnDelete` so a `helm upgrade` does not restart running gateways. Each pod then picks up the change when you delete it, in your own maintenance window.
- **External modules**: set `backend.externalModules.enabled` and `backend.externalModules.pvcName` (or the `frontend.` equivalents) to mount a PersistentVolumeClaim of `.modl` files, instead of building a custom image.
- **Certificate rotation and renewal**: `certManager.rotation.enabled` adds CronJobs that refresh the Gateway Network keystore on each gateway's volume. A running gateway only loads renewed certificates when it restarts, so pair it with `certManager.restartOnRenewal.enabled`, which restarts the gateways (Backup first) when the certificate secrets change.

## Upgrading from 4.0.0 or earlier

From 4.1.0 the frontend and backend StatefulSets are governed by the `<name>-frontend-headless` and `<name>-backend-headless` Services. Kubernetes does not allow `serviceName` to change on an existing StatefulSet, so `helm upgrade` from 4.0.0 or earlier is rejected. Delete only the StatefulSet objects first. Their pods and volumes keep running, and the upgraded StatefulSets adopt them:

```bash
kubectl delete statefulset ignition-scaleout-frontend ignition-scaleout-backend --cascade=orphan -n <namespace>
helm upgrade <release> ignition-charts/ignition-scaleout -n <namespace> ...
```

Turn on `backend.activeRouting.enabled` in a separate, later upgrade, once every pod has been replaced. Until the Master's pod is replaced it is only reachable under the old Service name, so the new Backup cannot sync with it. With active routing a Backup must be in sync to be Ready, so a combined upgrade would wait indefinitely (the Master keeps serving meanwhile).

Charts up to 3.1.0 ran the gateway as root by default. On storage that does not apply `fsGroup` (for example local-path), their data volumes are owned by root, and the upgraded gateway, which runs as `securityContext.runAsUser` (2003), cannot update them: the `preconfigure` init container fails with `Permission denied`. If your 3.x install did not set `securityContext.runAsUser`, also set `frontend.fixDataOwnership=true` and `backend.fixDataOwnership=true` for the upgrade, and set them back to `false` once the pods are running. They add an init container that changes the volume's owner as root, so the namespace must allow the baseline Pod Security level while they are on.

The [upgrading guide](https://apollogeddon.github.io/ignition-helm/docs/guides/upgrading/) covers both charts.

## Configuration

The most commonly changed values are below. Most `frontend.*` and `backend.*` values have the same meaning as the matching `ignition.*` value in the [failover chart](../failover/README.md#configuration). See [`values.yaml`](values.yaml) for every value, and the [chart reference](https://apollogeddon.github.io/ignition-helm/docs/charts/scaleout/) for the full defaults.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `applicationName` | Prefix of every resource the chart creates. | `ignition-scaleout` |
| `image.tag` | Ignition image tag for both layers. Empty uses the chart's `appVersion`. | `""` (8.3.1) |
| `frontend.secrets.GATEWAY_ADMIN_PASSWORD` | Frontend gateway admin password. Set your own. | `admin` |
| `backend.secrets.GATEWAY_ADMIN_PASSWORD` | Backend gateway admin password. Set your own. | `admin` |
| `frontend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for both layers' Gateway Network keystores. | `metro` |
| `backend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Must match `frontend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD`. | `metro` |
| `frontend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` / `backend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for each layer's web server TLS keystore. | `ignition` |
| `frontend.config.GATEWAY_MODULES_ENABLED` | Modules enabled on the frontend. | `perspective,symbol-factory` |
| `backend.config.GATEWAY_MODULES_ENABLED` | Modules enabled on the backend. | drivers, SQL Bridge, tag historian, reporting, alarm notification |
| `frontend.redundancy.replicas` | Number of frontend gateways. | `1` |
| `frontend.hpa.enabled` | Scale the frontend with a HorizontalPodAutoscaler (`minReplicas` 1, `maxReplicas` 10, `targetCPUUtilizationPercentage` 80). | `false` |
| `backend.redundancy.enabled` | Run the backend as a Master/Backup pair. | `false` |
| `backend.activeRouting.enabled` | Route user traffic only to the active backend gateway of a redundant pair: a labeller keeps `redundancy-active=true` on the active pod and the `<name>-backend-active` Service (which takes the configured service type, node ports and annotations) selects it. A Backup must also be in sync to be Ready. | `false` |
| `backend.persistence.size` | Size of each backend gateway's persistent volume. | `3Gi` |
| `frontend.service.type` / `backend.service.type` | Service type for each layer. | `NodePort` |
| `frontend.service.nodePorts` / `backend.service.nodePorts` | Optional static node ports (`http`, `https`, `gan`). | unset |
| `frontend.ingress.enabled` / `backend.ingress.enabled` | Create an Ingress for the layer. | `false` |
| `frontend.ingress.className` / `backend.ingress.className` | IngressClass name, for example `contour`; empty uses the cluster default. | `""` |
| `frontend.networkPolicy.enabled` / `backend.networkPolicy.enabled` | Create a NetworkPolicy that limits Gateway Network traffic to the chart's gateways. | `true` |
| `frontend.networkPolicy.extraIngress` / `backend.networkPolicy.extraIngress` | Extra NetworkPolicy ingress rules, for example the ingress controller's namespace or node CIDRs. | `[]` |
| `frontend.updateStrategy.type` / `backend.updateStrategy.type` | StatefulSet update strategy (`RollingUpdate` or `OnDelete`). | `RollingUpdate` |
| `frontend.externalModules.enabled` / `backend.externalModules.enabled` | Mount the layer's `externalModules.pvcName` PersistentVolumeClaim of modules. | `false` |
| `backend.restore.enabled` | Before the backend gateway starts, download a gateway backup from `backend.restore.url`, or copy it from `backend.restore.path`, to `/data/restore.gwbk` on the data volume. | `false` |
| `frontend.fixDataOwnership` / `backend.fixDataOwnership` | Change the data volume's owner to the gateway user on start (an init container running as root). Only for upgrades from charts up to 3.1.0 installed with the default root user. | `false` |
| `frontend.readinessProbe` / `frontend.livenessProbe` | Probe settings. Readiness fails while the gateway is still commissioning. | `/config/scripts/health-check.sh -t 3 -r` / `-t 5` |
| `backend.readinessProbe` / `backend.livenessProbe` | Probe settings. Readiness fails while the gateway is still commissioning; with `backend.activeRouting` a Backup must also be in sync. | `/config/scripts/health-check.sh -t 3 -r` / `-t 5` |
| `frontend.startupProbe.enabled` / `backend.startupProbe.enabled` | Add a startup probe, so slow starts are tolerated while liveness stays strict. | `false` |
| `frontend.lifecycle` / `backend.lifecycle` | Container lifecycle hooks, rendered as-is. | `{}` (none) |
| `frontend.logging.*` / `backend.logging.*` | `level`, per-logger `loggers`, SQLite log database maintenance (`sqlite`) and `wrapperLogToStdout`, as in the failover chart. | `INFO`, `{}`, `{}`, `true` |
| `frontend.emptyDirSizeLimit` / `backend.emptyDirSizeLimit` | Optional `sizeLimit` for the `logs`, `temp` and `dotIgnition` emptyDir volumes. | `""` each (no limit) |
| `certManager.issuer.name` / `certManager.issuer.kind` | The cert-manager issuer that signs the Gateway Network CA. | `cluster-issuer` / `ClusterIssuer` |
| `certManager.rotation.enabled` | CronJobs that refresh the Gateway Network keystore on each gateway's volume; renewed certificates load on the next restart (see `certManager.restartOnRenewal.enabled`). | `false` |
| `certManager.restartOnRenewal.enabled` | CronJob that starts a rolling restart (Backup first) when the Gateway Network or web certificate secrets change, so renewed certificates are loaded. | `false` |
| `affinity.enabled` | Pod anti-affinity between the gateways. `affinity.type` is not set in this chart's defaults, which gives required (hard) anti-affinity; set it to `soft` for preferred. | `false` |
