# Ignition failover Helm chart

`ignition-failover` deploys Inductive Automation's Ignition on Kubernetes as a single gateway or as a Master/Backup redundant pair. Use it when one gateway, or one redundant pair, serves both your devices and your users. For separate frontend and backend gateways, see [`ignition-scaleout`](../scaleout/README.md).

## Features

- **Redundancy**: one gateway by default, or a Master (pod 0) and Backup (pod 1) pair with `ignition.redundancy.enabled`.
- **Automatic configuration**: an init container writes the redundancy settings, including the peer address, to each gateway's data volume on every start, so the pair connects without using the Gateway web UI.
- **Certificate management**: cert-manager issues the Gateway Network certificates from a CA the chart creates, and the init container installs them into each gateway.
- **Persistent state**: a StatefulSet gives each gateway a stable network identity and its own persistent volume.

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

Install a single gateway with the release name `my-ignition`:

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```

Install a Master/Backup pair:

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.redundancy.enabled=true \
  --set ignition.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```

Resources are named after `applicationName` (default `ignition-failover`), not the release name: the StatefulSet is `ignition-failover` and its pods are `ignition-failover-0` and `ignition-failover-1`. Set `applicationName` to install more than one release in a namespace.

## Operations

- **Controlled rollouts**: set `ignition.updateStrategy.type` to `OnDelete` so a `helm upgrade` does not restart running gateways. Each pod then picks up the change when you delete it, in your own maintenance window.
- **External modules**: set `ignition.externalModules.enabled` and `ignition.externalModules.pvcName` to mount a PersistentVolumeClaim of `.modl` files, instead of building a custom image.
- **Health checks and shutdown**: the probes check that `/StatusPing` reports `RUNNING`, which works on Ignition 8.1 and 8.3. Readiness (`health-check.sh -r`) also fails while the gateway is still commissioning; liveness does not, so a gateway stuck commissioning is not restarted in a loop. There is no default `preStop` hook: on `SIGTERM` the gateway shuts down gracefully, and `gwcmd.sh -p` (used by 4.1.0) resets the gateway login password.
- **Certificate rotation and renewal**: `certManager.rotation.enabled` adds CronJobs that refresh the Gateway Network keystore on each gateway's volume. A running gateway only loads renewed certificates when it restarts, so pair it with `certManager.restartOnRenewal.enabled`, which restarts the gateways (Backup first) when the certificate secrets change.

## Upgrading from 4.0.0 or earlier

From 4.1.0 the StatefulSet is governed by the `<name>-headless` Service. Kubernetes does not allow `serviceName` to change on an existing StatefulSet, so `helm upgrade` from 4.0.0 or earlier is rejected. Delete only the StatefulSet object first. Its pods and volumes keep running, and the upgraded StatefulSet adopts them and replaces the Backup before the Master:

```bash
kubectl delete statefulset ignition-failover --cascade=orphan -n <namespace>
helm upgrade <release> ignition-charts/ignition-failover -n <namespace> ...
```

On start the gateways apply the chart's redundancy settings to their volumes, including the peer address under the new Service name, so the pair reconnects once both pods have been replaced.

Turn on `ignition.activeRouting.enabled` in a separate, later upgrade, once every pod has been replaced. Until the Master's pod is replaced it is only reachable under the old Service name, so the new Backup cannot sync with it. With active routing a Backup must be in sync to be Ready, so a combined upgrade would wait indefinitely (the Master keeps serving meanwhile).

Charts up to 3.1.0 ran the gateway as root by default. On storage that does not apply `fsGroup` (for example local-path), their data volumes are owned by root, and the upgraded gateway, which runs as `securityContext.runAsUser` (2003), cannot update them: the `preconfigure` init container fails with `Permission denied`. If your 3.x install did not set `securityContext.runAsUser`, also set `ignition.fixDataOwnership=true` for the upgrade, and set it back to `false` once the pods are running. It adds an init container that changes the volume's owner as root, so the namespace must allow the baseline Pod Security level while it is on.

The [upgrading guide](https://apollogeddon.github.io/ignition-helm/docs/guides/upgrading/) covers both charts.

## Configuration

The most commonly changed values are below. See [`values.yaml`](values.yaml) for every value, and the [chart reference](https://apollogeddon.github.io/ignition-helm/docs/charts/failover/) for the full defaults.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `applicationName` | Name of every resource the chart creates. | `ignition-failover` |
| `image.repository` | Ignition image repository. | `inductiveautomation/ignition` |
| `image.tag` | Ignition image tag. Empty uses the chart's `appVersion`; 8.1.53 and 8.3.1 are tested. | `""` (8.3.1) |
| `ignition.secrets.GATEWAY_ADMIN_USERNAME` | Gateway admin user name. | `admin` |
| `ignition.secrets.GATEWAY_ADMIN_PASSWORD` | Gateway admin password. Set your own. | `admin` |
| `ignition.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for the Gateway Network keystore. | `metro` |
| `ignition.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for the web server TLS keystore. | `ignition` |
| `ignition.sealedSecrets` | Render `ignition.secrets` as a SealedSecret of already encrypted values. | `false` |
| `ignition.config` | Gateway environment variables (edition, EULA, enabled modules). | see `values.yaml` |
| `ignition.redundancy.enabled` | Deploy a Master/Backup pair (2 replicas) instead of one gateway. Changing it, or any other `ignition.redundancy.*` value, on an existing install restarts the gateways and applies the role (Master, Backup, or Independent when turned off) and settings to their data volumes on start. | `false` |
| `ignition.activeRouting.enabled` | Route user traffic only to the active gateway of a redundant pair: a labeller keeps `redundancy-active=true` on the active pod, the `<name>-active` Service (which takes the configured service type, node ports and annotations) selects it, and the Ingress points at it. Readiness also requires a Backup to be in sync. | `false` |
| `ignition.resources` | Gateway CPU and memory requests and limits. | requests `500m`/`1Gi`, limits `1000m`/`2Gi` |
| `ignition.persistence.size` | Size of each gateway's persistent volume. | `3Gi` |
| `ignition.persistence.storageClassName` | Storage class; empty uses the cluster default. | `""` |
| `ignition.service.type` | Service type (`ClusterIP`, `NodePort` or `LoadBalancer`). | `NodePort` |
| `ignition.service.nodePorts` | Optional static node ports (`http`, `https`, `gan`). | unset |
| `ignition.ingress.enabled` | Create an Ingress. | `false` |
| `ignition.ingress.className` | IngressClass name, for example `contour`; empty uses the cluster default. | `""` |
| `ignition.ssl.enabled` | Serve HTTPS with your own PKCS#12 keystore from the `ignition.ssl.secretName` Secret (default `<name>-web-tls`). | `false` |
| `ignition.restore.enabled` | Before the gateway starts, download a gateway backup (`.gwbk`) from `ignition.restore.url`, or copy it from `ignition.restore.path`, to `/data/restore.gwbk` on the data volume. | `false` |
| `ignition.networkPolicy.enabled` | Create a NetworkPolicy that limits Gateway Network traffic to the chart's gateways. | `true` |
| `ignition.networkPolicy.extraIngress` | Extra NetworkPolicy ingress rules, for example the ingress controller's namespace or node CIDRs. | `[]` |
| `ignition.serviceMonitor.enabled` | Create a Prometheus Operator ServiceMonitor. | `false` |
| `ignition.updateStrategy.type` | StatefulSet update strategy (`RollingUpdate` or `OnDelete`). | `RollingUpdate` |
| `ignition.externalModules.enabled` | Mount the `ignition.externalModules.pvcName` PersistentVolumeClaim of modules. | `false` |
| `ignition.fixDataOwnership` | Change the data volume's owner to the gateway user on start (an init container running as root). Only for upgrades from charts up to 3.1.0 installed with the default root user. | `false` |
| `ignition.readinessProbe` / `ignition.livenessProbe` | Probe settings. A configured `command` is used as-is; the chart's health check (`/StatusPing` must report `RUNNING`) is the fallback when it is empty. Readiness adds `-r`: not Ready while the gateway is still commissioning, and with active routing a Backup must also be in sync. | `/config/scripts/health-check.sh -t 3 -r` / `-t 5` |
| `ignition.startupProbe.enabled` | Add a startup probe, so slow starts are tolerated while liveness stays strict. | `false` |
| `ignition.lifecycle` | Container lifecycle hooks, rendered as-is. | `{}` (none) |
| `ignition.logging.level` | Root log level (`INFO`, `DEBUG`, `WARN`, `ERROR`). | `INFO` |
| `ignition.logging.loggers` | Per-logger levels, for example `{"gateway.SslManager": "DEBUG"}`. | `{}` |
| `ignition.logging.wrapperLogToStdout` | Append `wrapper.logfile=/dev/stdout` to `args`, so the gateway log goes to the container log instead of an unrotated `logs/wrapper.log`. Skipped when `args` already sets `wrapper.logfile`. | `true` |
| `ignition.logging.sqlite` | SQLite log database maintenance (`entryLimit`, `maxEventsPerMaintenance`, `minTimeBetweenMaintenance`, `vacuumFrequency`). | `{}` (Ignition defaults) |
| `ignition.emptyDirSizeLimit` | Optional `sizeLimit` for the `logs`, `temp` and `dotIgnition` emptyDir volumes. | `""` each (no limit) |
| `certManager.issuer.name` / `certManager.issuer.kind` | The cert-manager issuer that signs the Gateway Network CA. | `cluster-issuer` / `ClusterIssuer` |
| `certManager.rotation.enabled` | CronJobs that refresh the Gateway Network keystore on each gateway's volume; renewed certificates load on the next restart (see `certManager.restartOnRenewal.enabled`). | `false` |
| `certManager.restartOnRenewal.enabled` | CronJob that starts a rolling restart (Backup first) when the Gateway Network or web certificate secrets change, so renewed certificates are loaded. | `false` |
| `affinity.enabled` | Pod anti-affinity between the gateways; `affinity.type` is `soft` (preferred) or `hard` (required). | `false` |
