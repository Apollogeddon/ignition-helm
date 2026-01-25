---
title: Features & Capabilities
description: Explore the advanced capabilities of the Ignition Helm Charts.
---

This library is designed to be "batteries-included" but highly extensible. Below are the core features categorised by their operational domain.

## 1. Automated Operations

The charts use a specialised **Init Container** (`preconfigure`) to handle complex setup tasks before the Ignition Gateway starts.

* **Redundancy Seeding**: Automatically configures the Backup node to pair with the Master, eliminating manual redundancy setup.
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

Set the root logging level for the console output.

```yaml
ignition:
  logging:
    level: "DEBUG" # INFO, WARN, ERROR
```

## 4. High Availability (HA)

### Probes (Health Checks)

Kubernetes checks if the Gateway is alive and ready to receive traffic.

* **Readiness**: Checks if the web server is responding (HTTP 200).
* **Liveness**: Checks if the process is running.

**Tip:** Increase `initialDelaySeconds` if your gateway loads a large project backup on startup.

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

* **Non-Root User**: Runs as UID `2003` by default.
* **SealedSecrets**: Support for Bitnami SealedSecrets for managing sensitive values without checking plain-text passwords into Git.

#### Example: Using SealedSecrets

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

## 6. Backup & Restore

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
