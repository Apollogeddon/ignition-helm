# Ignition scaleout Helm chart

`ignition-scaleout` deploys Inductive Automation's Ignition on Kubernetes in a scaleout architecture: backend gateways that run devices, databases and tag history, and frontend gateways that serve Perspective sessions and connect to the backend over the Gateway Network. Use it when user load needs to scale separately from device communication. For a single gateway or one redundant pair, see [`ignition-failover`](../failover/README.md).

## Features

- **Independent scaling**: scale the frontend gateways, manually or with a HorizontalPodAutoscaler on CPU and memory, without touching the backend.
- **Backend redundancy**: the backend can run as a Master/Backup pair with `backend.redundancy.enabled`.
- **Gateway Network setup**: cert-manager issues each layer's Gateway Network certificates from a CA the chart creates, and the frontends are configured to connect to the backend gateways.

## Architecture

- **Backend**: a StatefulSet of one gateway, or a redundant pair, with a persistent volume per gateway. Its EAM role is `Controller`.
- **Frontend**: a StatefulSet of `frontend.redundancy.replicas` gateways without persistent volumes. Its EAM role is `Agent`.

## Prerequisites

- Kubernetes, with a storage class that can provision persistent volumes.
- Helm.
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

### Verifying the chart

Each release carries a cosign signature bundle, `ignition-scaleout-<version>.tgz.sigstore.json`, made keyless by the repository's release pipeline (`version.yml`). To check a chart before installing it:

```bash
helm pull ignition-charts/ignition-scaleout --version <version>
gh release download ignition-scaleout-v<version> --repo Apollogeddon/ignition-helm --pattern '*.sigstore.json'
cosign verify-blob ignition-scaleout-<version>.tgz \
  --bundle ignition-scaleout-<version>.tgz.sigstore.json \
  --certificate-identity https://github.com/Apollogeddon/ignition-helm/.github/workflows/version.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

See [Verifying a chart](../../README.md#verifying-a-chart) for what this checks.

## Operations

- **Controlled rollouts**: set `frontend.updateStrategy.type` or `backend.updateStrategy.type` to `OnDelete` so a `helm upgrade` does not restart running gateways. Each pod then picks up the change when you delete it, in your own maintenance window.
- **External modules**: set `backend.externalModules.enabled` and `backend.externalModules.pvcName` (or the `frontend.` equivalents) to mount a PersistentVolumeClaim of `.modl` files, instead of building a custom image.
- **Certificate rotation and renewal**: `certManager.rotation.enabled` adds CronJobs that refresh the Gateway Network keystore on each backend gateway's volume. The frontends need none: their data volume is an emptyDir, rebuilt from the current certificate on every start, including autoscaled ones. A running gateway only loads renewed certificates when it restarts, so pair it with `certManager.restartOnRenewal.enabled`, which restarts the gateways (Backup first) when the certificate secrets change.

## Autoscaling the frontend

Set `frontend.hpa.enabled` to scale the frontend gateways with an `autoscaling/v2` HorizontalPodAutoscaler on CPU and/or memory utilization. It needs the [metrics server](https://github.com/kubernetes-sigs/metrics-server) (or another provider of the resource metrics API) in the cluster, and `componentSelectors: true`.

```yaml
componentSelectors: true
frontend:
  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
    behavior:
      scaleDown:
        stabilizationWindowSeconds: 600
        policies:
          - type: Pods
            value: 1
            periodSeconds: 300
```

- An autoscaler averages over the pods its StatefulSet selects. By default both StatefulSets select only on `app.kubernetes.io/name` and `app.kubernetes.io/instance`, which match the backend's pods as well, so the chart refuses `frontend.hpa.enabled` unless `componentSelectors` adds `app.kubernetes.io/component` to each selector. Kubernetes does not let a StatefulSet's selector change, so set it when you install. To turn it on for an existing release, delete only the StatefulSet objects first; their pods and volumes keep running, and the upgraded StatefulSets adopt them, as their pods already carry the component label:

  ```bash
  kubectl delete statefulset <name>-frontend <name>-backend -n <namespace> --cascade=orphan
  helm upgrade <release> ignition-charts/ignition-scaleout -n <namespace> ... --set componentSelectors=true
  ```

  With the autoscaler already on, the recreated frontend StatefulSet starts at one gateway until the autoscaler raises it to `minReplicas`, so do it in a quiet period. Turning `componentSelectors` off again needs the same step.
- While the autoscaler is enabled, the frontend StatefulSet leaves out `replicas`, so `helm upgrade` doesn't reset the count it has set. When you enable it on an existing release, Helm removes the field and Kubernetes briefly scales the StatefulSet to one gateway, until the autoscaler raises it to `minReplicas`. Enable it in a quiet period.
- A new frontend gateway takes minutes to start and commission, and scaling down ends the Perspective sessions on the gateways it removes, so scale down slowly with `behavior.scaleDown`.
- A PodDisruptionBudget (`minAvailable: 1`) protects the frontend while the autoscaler is enabled.
- The backend doesn't autoscale, and `backend.hpa.enabled` is refused. A backend is one gateway, or a Master/Backup pair, each with its own data volume, redundancy role and device connections: an extra backend pod would be neither Master nor Backup, and would open its own connections to the same devices and databases. Scale user load on the frontend instead.

## Upgrading

The frontend and backend StatefulSets are governed by the `<name>-frontend-headless` and `<name>-backend-headless` Services. Kubernetes does not allow `serviceName` to change on an existing StatefulSet, so if yours name other Services, `helm upgrade` is rejected. Delete only the StatefulSet objects first. Their pods and volumes keep running, and the upgraded StatefulSets adopt them:

```bash
kubectl delete statefulset ignition-scaleout-frontend ignition-scaleout-backend --cascade=orphan -n <namespace>
helm upgrade <release> ignition-charts/ignition-scaleout -n <namespace> ...
```

If you also want active routing, turn on `backend.activeRouting.enabled` in a separate, later upgrade, once every pod has been replaced. Until the Master's pod is replaced it is only reachable under the other Service's name, so the new Backup cannot sync with it. With active routing a Backup must be in sync to be Ready, so a combined upgrade would wait indefinitely (the Master keeps serving meanwhile).

The chart creates a NetworkPolicy by default that admits web traffic only from pods in the release's namespace. If your release has none from the chart yet, in the same upgrade add `frontend.networkPolicy.extraIngress` (and `backend.networkPolicy.extraIngress`, if the backend is reached from outside) rules for the traffic you rely on (an ingress controller's or Prometheus's namespace, or the node addresses behind a NodePort or LoadBalancer), as in the [examples](https://github.com/Apollogeddon/ignition-helm/tree/main/examples), or set `frontend.networkPolicy.enabled=false` and `backend.networkPolicy.enabled=false`. Otherwise the upgrade cuts that traffic off.

The gateways run as `securityContext.runAsUser` (2003). On storage that does not apply `fsGroup` (for example local-path), a data volume a gateway running as root wrote is owned by root, and the gateway cannot update it: the `preconfigure` init container fails with `Permission denied`. If your install ran the gateways as root, also set `frontend.fixDataOwnership=true` and `backend.fixDataOwnership=true` for the upgrade, and set them back to `false` once the pods are running. They add an init container that changes the volume's owner as root, so the namespace must allow the baseline Pod Security level while they are on.

The [upgrading guide](https://apollogeddon.github.io/ignition-helm/docs/guides/upgrading/) covers both charts.

## Configuration

The most commonly changed values are below. Most `frontend.*` and `backend.*` values have the same meaning as the matching `ignition.*` value in the [failover chart](../failover/README.md#configuration). See [`values.yaml`](values.yaml) for every value, and the [chart reference](https://apollogeddon.github.io/ignition-helm/docs/charts/scaleout/) for the full defaults.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `applicationName` | Prefix of every resource the chart creates. | `ignition-scaleout` |
| `componentSelectors` | Select each StatefulSet's pods by `app.kubernetes.io/component` too. Needed by `frontend.hpa`; set it at install, as a selector can't change (see [Autoscaling the frontend](#autoscaling-the-frontend)). | `false` |
| `image.tag` | Ignition image tag for both layers. Empty uses the chart's `appVersion`. | `""` |
| `frontend.secrets.GATEWAY_ADMIN_PASSWORD` | Frontend gateway admin password. Set your own. | `admin` |
| `backend.secrets.GATEWAY_ADMIN_PASSWORD` | Backend gateway admin password. Set your own. | `admin` |
| `frontend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` / `backend.secrets.IGNITION_GAN_KEYSTORE_PASSWORD` | Password for each layer's Gateway Network keystore. | `metro` |
| `frontend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` / `backend.secrets.IGNITION_WEB_KEYSTORE_PASSWORD` | Password for each layer's web server TLS keystore. | `ignition` |
| `frontend.config.GATEWAY_MODULES_ENABLED` | Modules enabled on the frontend. | `perspective,symbol-factory` |
| `backend.config.GATEWAY_MODULES_ENABLED` | Modules enabled on the backend. | drivers, SQL Bridge, tag historian, reporting, alarm notification |
| `frontend.redundancy.replicas` | Number of frontend gateways. | `1` |
| `frontend.hpa.enabled` | Scale the frontend with a HorizontalPodAutoscaler. The StatefulSet then leaves out `replicas`, so `frontend.redundancy.replicas` is ignored and the autoscaler owns the count. See [Autoscaling the frontend](#autoscaling-the-frontend). | `false` |
| `frontend.hpa.minReplicas` / `frontend.hpa.maxReplicas` | Fewest and most frontend gateways: whole numbers from 1 to 2147483647, with the minimum no higher than the maximum. | `1` / `10` |
| `frontend.hpa.targetCPUUtilizationPercentage` / `frontend.hpa.targetMemoryUtilizationPercentage` | Target average utilization, as a percentage of `frontend.resources.requests`; at least one is needed. Empty leaves that metric out. | `80` / `""` |
| `frontend.hpa.behavior` | The HPA's scaling `behavior` (`scaleUp`/`scaleDown` policies and stabilization windows), rendered as-is. | `{}` (Kubernetes defaults) |
| `backend.redundancy.enabled` | Run the backend as a Master/Backup pair. | `false` |
| `backend.activeRouting.enabled` | Route user traffic only to the active backend gateway of a redundant pair: a labeller keeps `redundancy-active=true` on the active pod and the `<name>-backend-active` Service (which takes the configured service type, node ports and annotations) selects it. A Backup must also be in sync to be Ready. | `false` |
| `backend.persistence.size` | Size of each backend gateway's persistent volume. | `3Gi` |
| `frontend.service.type` / `backend.service.type` | Service type for each layer. | `NodePort` |
| `frontend.service.nodePorts` / `backend.service.nodePorts` | Optional static node ports (`http`, `https`, `gan`). | unset |
| `frontend.ingress.enabled` / `backend.ingress.enabled` | Create an Ingress for the layer. | `false` |
| `frontend.ingress.className` / `backend.ingress.className` | IngressClass name, for example `contour`; empty uses the cluster default. | `""` |
| `frontend.networkPolicy.enabled` / `backend.networkPolicy.enabled` | Create a NetworkPolicy that limits Gateway Network traffic to the chart's gateways and web traffic to pods in the namespace. | `true` |
| `frontend.networkPolicy.extraIngress` / `backend.networkPolicy.extraIngress` | Extra NetworkPolicy ingress rules: needed for an ingress controller, Prometheus, or a NodePort or LoadBalancer Service, as in the [examples](https://github.com/Apollogeddon/ignition-helm/tree/main/examples). | `[]` |
| `frontend.updateStrategy.type` / `backend.updateStrategy.type` | StatefulSet update strategy (`RollingUpdate` or `OnDelete`). | `RollingUpdate` |
| `frontend.externalModules.enabled` / `backend.externalModules.enabled` | Mount the layer's `externalModules.pvcName` PersistentVolumeClaim of modules. | `false` |
| `backend.restore.enabled` | Restore a gateway backup from `backend.restore.url`, or a mounted `backend.restore.path`, on the backend gateway's first start. The backup is staged on the data volume once and the gateway starts with `-r`; later restarts keep the gateway's own changes. To restore again, start from an empty data volume. | `false` |
| `frontend.fixDataOwnership` / `backend.fixDataOwnership` | Change the data volume's owner to the gateway user on start (an init container running as root). Only for upgrading an install whose gateways ran as root. | `false` |
| `frontend.readinessProbe` / `frontend.livenessProbe` | Probe settings. Readiness fails while the gateway is still commissioning. | `/config/scripts/health-check.sh -t 3 -r` / `-t 5` |
| `backend.readinessProbe` / `backend.livenessProbe` | Probe settings. Readiness fails while the gateway is still commissioning; with `backend.activeRouting` a Backup must also be in sync. | `/config/scripts/health-check.sh -t 3 -r` / `-t 5` |
| `frontend.startupProbe.enabled` / `backend.startupProbe.enabled` | Add a startup probe, so slow starts are tolerated while liveness stays strict. | `false` |
| `frontend.lifecycle` / `backend.lifecycle` | Container lifecycle hooks, rendered as-is. | `{}` (none) |
| `frontend.logging.*` / `backend.logging.*` | `level`, per-logger `loggers`, SQLite log database maintenance (`sqlite`) and `wrapperLogToStdout`, as in the failover chart. | `INFO`, `{}`, `{}`, `true` |
| `frontend.emptyDirSizeLimit` / `backend.emptyDirSizeLimit` | Optional `sizeLimit` for the `logs`, `temp` and `dotIgnition` emptyDir volumes. | `""` each (no limit) |
| `certManager.issuer.name` / `certManager.issuer.kind` | The cert-manager issuer that signs the Gateway Network CA. | `cluster-issuer` / `ClusterIssuer` |
| `certManager.rotation.enabled` | CronJobs that refresh the Gateway Network keystore on each backend gateway's volume (the frontends rebuild theirs on every start); renewed certificates load on the next restart (see `certManager.restartOnRenewal.enabled`). | `false` |
| `certManager.restartOnRenewal.enabled` | CronJob that starts a rolling restart (Backup first) when the Gateway Network or web certificate secrets change, so renewed certificates are loaded. | `false` |
| `affinity.enabled` | Pod anti-affinity between this release's gateways of one layer (frontends apart, backends apart); `affinity.type` is `soft` (preferred, the default) or `hard` (required). | `false` |
