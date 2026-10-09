# Ignition common library chart

`ignition-common` is a Helm library chart shared by the `ignition-failover` and `ignition-scaleout` charts. It holds the templates, helper functions and gateway scripts both charts use, so the two deployment models stay consistent. It renders nothing on its own and is not meant to be installed directly.

## Templates

### Resources (`_resources.tpl`)

| Template | Renders |
| -------- | ------- |
| `ignition-common.serviceAccount` | A ServiceAccount. |
| `ignition-common.configMap` | A ConfigMap of gateway environment variables. |
| `ignition-common.secret` | An Opaque Secret, or a Bitnami SealedSecret, of sensitive environment variables. |
| `ignition-common.ganCA` | A cert-manager CA Certificate for the Gateway Network, issued by the configured issuer, and an Issuer that signs with it. |
| `ignition-common.ganMetroKeystore` | The Secret holding the Gateway Network keystore password. |
| `ignition-common.ganCertificate` | A cert-manager Certificate, with a PKCS#12 keystore, for one component's Gateway Network identity. |
| `ignition-common.pdb` | A PodDisruptionBudget. |
| `ignition-common.redundancyServices` | The `-primary` and `-backup` headless Services that target pod ordinals 0 and 1. |
| `ignition-common.networkPolicy` | A NetworkPolicy that limits Gateway Network traffic to the chart's gateways. |
| `ignition-common.serviceMonitor` | A Prometheus Operator ServiceMonitor. |
| `ignition-common.hpa` | A HorizontalPodAutoscaler. |
| `ignition-common.ganRotationCronJob` | CronJobs that refresh the Gateway Network keystore on each gateway's volume. |

### Active routing and certificate renewal

| Template | Renders |
| -------- | ------- |
| `ignition-common.activeRouting` (`_active.tpl`) | The labeller Deployment and `<name>-active` Service that route traffic to the active gateway of a redundant pair. |
| `ignition-common.certify` (`_certify.tpl`) | The CronJob that restarts the gateways when their certificate secrets change. |

### Helpers (`_helpers.tpl`)

| Template | Purpose |
| -------- | ------- |
| `ignition.name` | The application name (`applicationName`, else the chart name), used to name every resource. |
| `ignition.fullname` | The release-qualified name. |
| `ignition-common.service` / `ignition-common.headlessService` | The gateway Service and the StatefulSet's governing headless Service. |
| `ignition-common.ingress` | The gateway Ingress. |
| `ignition-common.podFQDN` | The in-cluster DNS name of a pod ordinal. |
| `ignition-common.volumes` / `ignition-common.volumeMounts` | The gateway's volumes and mounts. |
| `ignition-common.initContainer.preconfigure` | The init container that prepares the data volume before the gateway starts. |
| `ignition-common.containerProbes` | The readiness, liveness and startup probes and lifecycle hooks. |

### Scripts (`_scripts.tpl`)

`ignition-common.scripts` renders a Secret of the scripts the gateways run. The main ones are:

| Script | Purpose |
| ------ | ------- |
| `seed-data-volume.sh` | Seeds the persistent data volume from the image on first start. |
| `seed-redundancy.sh` | Applies the chart's redundancy role and settings to `redundancy.xml` on every start. |
| `prepare-gan-certificates.sh` | Installs the Gateway Network certificates into the gateway's data directory. |
| `prepare-tls-certificates.sh` | Installs a custom web server keystore when `ssl.enabled` is set. |
| `active-routing.sh` | The labeller loop behind active routing. |
| `certify.sh` | Restarts the gateways when their certificate secrets change. |
| `health-check.sh` | The probe script: checks that `/StatusPing` reports `RUNNING`, and with `-r` that the gateway has finished commissioning. |

## Usage

Add the chart as a dependency of an application chart:

```yaml
dependencies:
  - name: ignition-common
    version: "*"
    repository: "file://../common"
```

Then include its templates. Most take a dict with the component's values and the root context:

```yaml
{{ include "ignition-common.service" (dict "values" .Values.ignition "Release" .Release "Chart" .Chart "Values" .Values) }}
{{- include "ignition-common.networkPolicy" (dict "values" .Values.ignition "context" .) }}
```

Each template's parameters are documented in a comment above its `define`.
