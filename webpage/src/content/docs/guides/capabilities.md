---
title: Features & Capabilities
description: Explore the advanced capabilities of the Ignition Helm Charts.
---

This library is designed to be "batteries-included" but highly extensible. Below are the core features categorised by their operational domain.

## 1. Automated Operations

The charts use a specialised **Init Container** (`preconfigure`) to handle complex setup tasks before the Ignition Gateway starts.

* **Redundancy Settings**: Configures pod 0 as Master and pod 1 as Backup, and re-applies the chart's redundancy settings on **every** start. Turning `redundancy.enabled` on or off, or changing any `redundancy.*` value, restarts the gateways and takes effect without using the Gateway UI (turning it off makes the gateway Independent).
* **Certificate Exchange**: If `cert-manager` is not present, it auto-generates self-signed certificates for the Gateway Network (GAN) and shares them between pods via Kubernetes Secrets.
* **Auto-Restore**: Checks for a `.gwbk` file in mounted volumes or at a specified URL and restores it on first startup.

## 2. Storage & Persistence

Ignition requires persistence for `data/db` (config) and logs.

### Persistent Volume Claims (PVC)

By default, each pod gets a dedicated 3Gi volume.

```yaml
persistence:
  size: 3Gi
  accessModes: [ "ReadWriteOnce" ]
```

### Advanced Mounting (`extraVolumes`)

Mount arbitrary Kubernetes volumes (ConfigMaps, Secrets, existing PVCs) into the container.

#### Example: Mounting a custom JDBC driver

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

### Local Development Mounts

For local dev (Kind/Docker Desktop), map a host folder directly into the container.

```yaml
ignition:
  localMounts:
    - hostPath: "C:/MyProjects/Ignition/Themes"
      mountPath: "data/themes"
```

## 3. Configuration & Logging

### Environment Variables

Configure the gateway using standard Ignition environment variables.

```yaml
ignition:
  config:
    IGNITION_EDITION: "edge"
    GATEWAY_ADMIN_USERNAME: "admin"
    GATEWAY_MODULES_ENABLED: "perspective,opc-ua"
```

### JVM Arguments

Pass custom flags to the Java runtime.

```yaml
ignition:
  args:
    - -m
    - "2048" # Max Memory (MB)
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

## 4. High Availability (HA)

### Probes (Health Checks)

Kubernetes checks if the Gateway is alive and ready to receive traffic.

* **Readiness** (`health-check.sh -t 3 -r`): `/StatusPing` must report `RUNNING`, and the gateway must have finished commissioning. With `activeRouting`, a Backup must also be in sync with its Master.
* **Liveness** (`health-check.sh -t 5`): `/StatusPing` must report `RUNNING`. A gateway stuck commissioning is not restarted in a loop.
* **Startup** (optional, `startupProbe.enabled`): holds liveness off during slow starts, such as a Backup restoring a state transfer from its Master.

The checks use `/StatusPing`, which works on Ignition 8.1 and 8.3. A probe `command` you set is used as-is.

### Active Routing

By default every Ready gateway sits behind the Service, and a cold Backup is Ready too, so users can land on a gateway that is not serving. With `activeRouting.enabled` (failover, or the scaleout backend) a small labeller marks the Active gateway and a `<name>-active` Service sends traffic only there. It takes over the configured Service type, nodePorts and annotations, and the chart Ingress points at it.

```yaml
ignition:
  redundancy:
    enabled: true
  activeRouting:
    enabled: true
```

Failover then takes a few seconds: about 4-5 s for a graceful stop of the Master and 2-3 s for a crash, measured on a test cluster. When upgrading from 4.0.0 or earlier, enable it in a separate upgrade (see [Upgrading](../upgrading/)).

### Pod Scheduling (Affinity)

Ensure high availability by forcing Master and Backup pods to run on different physical nodes.

```yaml
affinity:
  enabled: true
  type: "hard" # "hard" = Required, "soft" = Preferred
  topologyKey: "kubernetes.io/hostname"
```

### Pod Disruption Budgets (PDB)

To prevent downtime during cluster maintenance (like node upgrades), the charts automatically deploy a **Pod Disruption Budget**. This instructs Kubernetes to ensure at least one node in a redundant pair remains available at all times.

## 5. Security

* **Non-Root User**: Runs as UID `2003` with `runAsNonRoot: true`, no privilege escalation and all capabilities dropped. The charts' pods meet the Kubernetes **restricted** Pod Security level.
* **SealedSecrets**: Support for Bitnami SealedSecrets for managing sensitive values without checking plain-text passwords into Git.
* **Network Isolation (NetworkPolicy)**: Optionally restrict traffic to the Gateway Network (GAN) so only authenticated Ignition pods can communicate on port `8060`.

```yaml
ignition:
  networkPolicy:
    enabled: true
```

### Example: Using SealedSecrets

If you have the `kubeseal` CLI and SealedSecrets controller installed:

1. Set `sealedSecrets: true` in your values.
2. Provide the *encrypted* strings in the `secrets` map.

```yaml
ignition:
  sealedSecrets: true
  secrets:
    GATEWAY_ADMIN_PASSWORD: "AgBy38v4Sly6S..." # Encrypted via kubeseal
```

### Ingress & Sticky Sessions

Ignition Perspective and Vision sessions are stateful. When using an Ingress (like Nginx), you **must** enable sticky sessions (session affinity) to ensure clients stay connected to the same pod.

```yaml
ignition:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/affinity: "cookie"
      nginx.ingress.kubernetes.io/session-cookie-name: "route"
```

### Custom Web Server SSL

You can provide your own PKCS#12 keystore for the Web Server (HTTPS) instead of the default self-signed one.

1. Create a Kubernetes Secret containing your `keystore.p12` file.
2. Ensure the keystore password matches the value set in `IGNITION_WEB_KEYSTORE_PASSWORD`.
3. Enable SSL in your `values.yaml`:

```yaml
ignition:
  ssl:
    enabled: true
    secretName: "my-custom-keystore"
```

## 6. Observability & Scaling

### Prometheus Monitoring

The charts support the **Prometheus Operator** via a `ServiceMonitor` resource. This allows automatic discovery of your gateways by Prometheus.

**Prerequisite**: You must expose a Prometheus-compatible endpoint on your gateway. Common methods include:

* **OpenTelemetry Java Agent**: The modern approach for Ignition 8.1+. Automatically instruments the JVM and Ignition metrics.
* **WebDev Script**: A simple Python script within the WebDev module to format system tags for Prometheus.

```yaml
ignition:
  serviceMonitor:
    enabled: true
    interval: "30s"
    path: "/data/metrics" # Update this to match your endpoint (e.g., /metrics)
```

### Horizontal Pod Autoscaling (HPA)

In the **Scaleout** architecture, you can dynamically scale your **Frontend** nodes based on CPU or Memory utilization. This is ideal for handling variable user loads in Perspective sessions.

```yaml
frontend:
  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
```

### Graceful Shutdown

Ignition shuts down cleanly on `SIGTERM`, so the charts add no `preStop` hook. `gwcmd.sh -p` resets the gateway login password and must not be used as one.

### Certificate Renewal

cert-manager renews the Gateway Network certificates, but a running gateway only loads them when it starts. `certManager.restartOnRenewal.enabled` adds a CronJob that notices when the certificate secrets change and rolls the gateways, Backup first.

```yaml
certManager:
  restartOnRenewal:
    enabled: true
```

## 7. Backup & Restore

### Automated Restore

Seed a new gateway from a backup file on startup.

```yaml
ignition:
  restore:
    enabled: true
    url: "https://internal-server/backups/production.gwbk"
```

### Manual Backup (CLI)

To take a snapshot of a running gateway without logging into the GUI:

```bash
# Execute the backup command inside the pod
kubectl exec -it ignition-failover-0 -- /usr/local/bin/ignition/gwcmd.sh -b /usr/local/bin/ignition/data/backup.gwbk

# Copy the file to your local machine
kubectl cp ignition-failover-0:/usr/local/bin/ignition/data/backup.gwbk ./backup.gwbk
```
