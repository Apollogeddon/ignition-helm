---
title: Capabilities
order: 3
description: What the Ignition Helm charts do, grouped by area, with example values.
---

This page describes what the charts do and how to configure each feature. The examples use the failover chart's `ignition.` prefix; in the scaleout chart, use `frontend.` or `backend.` instead.

## Automated setup

The `preconfigure` init container prepares each gateway before it starts:

* **Data volume**: seeds the persistent volume from the image on first start.
* **Redundancy settings**: configures pod 0 as Master and pod 1 as Backup, and re-applies the chart's redundancy settings on every start. Turning `redundancy.enabled` on or off, or changing any `redundancy.*` value, restarts the gateways and takes effect without using the Gateway web UI (turning it off makes the gateway Independent).
* **Gateway Network certificates**: installs the certificate and CA that cert-manager issued into the gateway's keystore. The chart creates the CA `Certificate`, an `Issuer` that signs with it, and a `Certificate` per component, so cert-manager and an issuer for the CA are required.
* **Gateway backup**: with `restore.enabled`, restores a `.gwbk` file from `restore.url`, or a mounted `restore.path`, on the gateway's first start.

## Storage and persistence

### Persistent volumes

Each failover gateway, and each scaleout backend gateway, gets its own persistent volume, 3Gi by default. Scaleout frontend gateways have no persistent volume.

```yaml
ignition:
  persistence:
    size: 3Gi
    accessModes: ["ReadWriteOnce"]
```

### Extra volumes

Mount other Kubernetes volumes (ConfigMaps, Secrets, existing PersistentVolumeClaims) into the gateway container with `extraVolumes` and `extraVolumeMounts`.

For example, to mount a custom JDBC driver:

```yaml
ignition:
  extraVolumes:
    - name: jdbc-driver-vol
      configMap:
        name: my-jdbc-drivers
  extraVolumeMounts:
    - name: jdbc-driver-vol
      mountPath: /usr/local/bin/ignition/user-lib/jdbc
```

### Local development mounts

For local development (kind or Docker Desktop), mount a host directory into the gateway's installation directory. `mountPath` is relative to `/usr/local/bin/ignition`.

```yaml
ignition:
  localMounts:
    - hostPath: "C:/MyProjects/Ignition/Themes"
      mountPath: "data/themes"
```

## Configuration and logging

### Environment variables

`config` sets the gateway's environment variables, through a ConfigMap. Use it for the Ignition image's standard variables:

```yaml
ignition:
  config:
    IGNITION_EDITION: "edge"
    GATEWAY_MODULES_ENABLED: "perspective,opc-ua"
```

Put sensitive values, such as `GATEWAY_ADMIN_PASSWORD`, in `secrets` instead, which the chart renders as a Secret.

### Gateway arguments

`args` is passed to the Ignition image's entrypoint. `-m` sets the maximum heap in MB, `-n` the gateway name, and anything after `--` is passed to the gateway as wrapper and JVM settings. Setting `args` replaces the whole default list, so keep `-n` and the default `--` entry:

```yaml
ignition:
  args:
    - -m
    - "2048"
    - -n
    - "$(GATEWAY_SYSTEM_NAME)"
    - --
    - gateway.useProxyForwardedHeader=true
    - -Dignition.allowunsignedmodules=true
```

### Logging

The gateway log goes to the container log (`kubectl logs`, rotated by the kubelet) by default: `logging.wrapperLogToStdout` adds `wrapper.logfile=/dev/stdout` to the gateway args. Without it Ignition writes an unrotated `logs/wrapper.log` that can fill the logs volume and get the pod evicted.

```yaml
ignition:
  logging:
    level: "INFO"            # root level: INFO, DEBUG, WARN, ERROR
    loggers:                 # per-logger levels
      gateway.SslManager: WARN
    sqlite:                  # the gateway's log database (unset keys keep Ignition defaults)
      entryLimit: 20000
  emptyDirSizeLimit:
    logs: 512Mi              # optional cap on the logs volume
```

## High availability

### Probes

Kubernetes uses the probes to decide whether a gateway is alive and ready for traffic.

* **Readiness** (`health-check.sh -t 3 -r`): `/StatusPing` must report `RUNNING`, and the gateway must have finished commissioning. With `activeRouting`, a Backup must also be in sync with its Master.
* **Liveness** (`health-check.sh -t 5`): `/StatusPing` must report `RUNNING`. A gateway stuck commissioning is not restarted in a loop.
* **Startup** (optional, `startupProbe.enabled`): holds liveness off during slow starts, such as a Backup restoring a state transfer from its Master.

The checks use `/StatusPing`, which works on Ignition 8.1 and 8.3. A probe `command` you set is used as-is.

### Active routing

By default every Ready gateway sits behind the Service, and a cold Backup is Ready too, so users can land on a gateway that is not serving. With `activeRouting.enabled` (failover, or the scaleout backend) a small labeller marks the active gateway and a `<name>-active` Service sends traffic only there. It takes over the configured Service type, node ports and annotations, and the chart Ingress points at it.

```yaml
ignition:
  redundancy:
    enabled: true
  activeRouting:
    enabled: true
```

Failover then takes a few seconds: about 4-5 s for a graceful stop of the Master and 2-3 s for a crash, measured on a test cluster. When upgrading from 4.0.0 or earlier, enable it in a separate upgrade (see [Upgrading](../upgrading/)).

### Pod anti-affinity

Keep the Master and Backup on different nodes with pod anti-affinity:

```yaml
affinity:
  enabled: true
  type: "hard" # "hard" = Required, "soft" = Preferred
  topologyKey: "kubernetes.io/hostname"
```

### Pod disruption budgets

To keep a gateway available during voluntary disruptions such as node drains, the charts create a PodDisruptionBudget with `minAvailable: 1` for a redundant pair (failover or scaleout backend), and for the scaleout frontend when it has more than one replica or an autoscaler.

## Security

* **Non-root user**: the gateways run as UID `2003` with `runAsNonRoot: true`, no privilege escalation and all capabilities dropped. The charts' pods meet the Kubernetes restricted Pod Security level (except the optional `fixDataOwnership` init container).
* **SealedSecrets**: `sealedSecrets: true` renders the `secrets` map as a Bitnami SealedSecret, so you can keep encrypted values in Git.
* **Network isolation**: a NetworkPolicy, on by default, allows Gateway Network traffic (port `8060`) only from the chart's own gateways.

```yaml
ignition:
  networkPolicy:
    enabled: true
```

### Example: SealedSecrets

With the SealedSecrets controller in the cluster and the `kubeseal` CLI:

1. Set `sealedSecrets: true` in your values.
2. Provide the *encrypted* strings in the `secrets` map.

```yaml
ignition:
  sealedSecrets: true
  secrets:
    GATEWAY_ADMIN_PASSWORD: "AgBy38v4Sly6S..." # Encrypted via kubeseal
```

### Ingress and sticky sessions

Perspective and Vision sessions are stateful. When more than one gateway can serve a client, for example scaleout frontends behind an Ingress, enable sticky sessions so each client stays on the same pod. With ingress-nginx:

```yaml
frontend:
  ingress:
    enabled: true
    className: nginx
    annotations:
      nginx.ingress.kubernetes.io/affinity: "cookie"
      nginx.ingress.kubernetes.io/session-cookie-name: "route"
```

### Custom web server certificate

You can give the gateway's web server (HTTPS) your own PKCS#12 keystore. The chart does not issue web server certificates; you provide the Secret, for example from your own cert-manager `Certificate`.

1. Create a Secret with your keystore under the key `keystore.p12`.
2. Set `IGNITION_WEB_KEYSTORE_PASSWORD` in `secrets` to the keystore's password.
3. Enable it in your values. `secretName` defaults to `<name>-web-tls`.

```yaml
ignition:
  ssl:
    enabled: true
    secretName: "my-custom-keystore"
```

## Observability and scaling

### Prometheus monitoring

The charts can create a Prometheus Operator `ServiceMonitor`, so Prometheus discovers the gateways.

The gateway does not expose Prometheus metrics by default, so you need to add an endpoint, for example:

* **OpenTelemetry Java agent**: instruments the gateway's JVM.
* **WebDev script**: a script in the WebDev module that formats tag values for Prometheus.

```yaml
ignition:
  serviceMonitor:
    enabled: true
    interval: "30s"
    path: "/data/metrics" # Update this to match your endpoint (e.g., /metrics)
```

### Horizontal pod autoscaling

In the scaleout chart, a HorizontalPodAutoscaler can scale the frontend gateways on CPU utilization (`targetCPUUtilizationPercentage`), memory utilization (`targetMemoryUtilizationPercentage`) or both, for variable Perspective load.

```yaml
frontend:
  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
```

### Graceful shutdown

Ignition shuts down cleanly on `SIGTERM`, so the charts add no `preStop` hook. Do not use `gwcmd.sh -p` as one: it resets the gateway login password.

### Certificate renewal

cert-manager renews the Gateway Network certificates, but a running gateway only loads them when it starts. `certManager.restartOnRenewal.enabled` adds a CronJob that notices when the certificate secrets change and restarts the gateways, Backup first.

```yaml
certManager:
  restartOnRenewal:
    enabled: true
```

## Backup and restore

### Restore on first start

Restore a gateway backup when the gateway first starts. The init container stages the backup on the data volume once, and the gateway starts with `-r` on it. Ignition restores it on the gateway's first start only, so later restarts keep any changes made since. To restore again, start from an empty data volume.

```yaml
ignition:
  restore:
    enabled: true
    url: "https://internal-server/backups/production.gwbk"
```

### Manual backup

To take a backup of a running gateway without the web UI:

```bash
# Run the backup inside the pod
kubectl exec -it ignition-failover-0 -- /usr/local/bin/ignition/gwcmd.sh -b /usr/local/bin/ignition/data/backup.gwbk

# Copy the file to your local machine
kubectl cp ignition-failover-0:/usr/local/bin/ignition/data/backup.gwbk ./backup.gwbk
```
