---
title: Advanced Configuration
description: Best practices for production-grade Ignition deployments.
---

This guide covers advanced configuration patterns for securing, monitoring, and scaling your Ignition Helm deployments.

## 1. Database Integration

While you can configure database connections manually via the Ignition Gateway UI, it is best practice to manage credentials securely via Kubernetes.

### Using Environment Variables

You can pass database connection details into the gateway using the `config` and `secrets` maps. These become system environment variables that can be referenced in Ignition.

**values.yaml:**

```yaml
ignition:
  config:
    DB_HOST: "postgres-service.database.svc.cluster.local"
    DB_NAME: "ignition_data"
    DB_USER: "ignition_admin"
  secrets:
    DB_PASSWORD: "my-secure-password"
```

In the Ignition Gateway UI (or your `.gwbk` backup), you can then reference these values using the syntax `${DB_HOST}`, `${DB_USER}`, etc., in the database connection settings.

---

## 2. Production Monitoring

For production environments, we recommend using the **Prometheus Operator** to collect metrics.

### Prerequisites

1. **Expose Metrics**: Ensure your gateway exposes a `/metrics` (or similar) endpoint. We recommend using the **OpenTelemetry Java Instrumentation agent** for deep visibility, or a custom **WebDev** script for tag-specific data.
2. **Operator Installation**: Ensure the Prometheus Operator is running in your cluster.

### Enabling Scaping

Enable the `serviceMonitor` in your `values.yaml` to allow Prometheus to automatically discover and scrape your pods.

```yaml
ignition:
  serviceMonitor:
    enabled: true
    interval: "15s"
    path: "/data/metrics" # Match the path of your chosen exporter
```

---

## 3. Horizontal Scaling (Scaleout)

The **Scaleout** architecture allows you to scale the **Frontend** layer independently. This is particularly useful for Perspective-heavy applications where user session load fluctuates.

### Configuring the HPA

The `ignition-scaleout` chart supports the **HorizontalPodAutoscaler (HPA)**.

```yaml
frontend:
  redundancy:
    replicas: 2 # Minimum starting replicas
  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Why Scale on CPU?

Perspective sessions are processed on the Gateway (Frontend). Each active session consumes CPU cycles for script execution and binding evaluations. Scaling based on CPU utilization ensures that new Frontend nodes are spun up before existing nodes become sluggish.

---

## 4. Network Security (GAN Isolation)

The Gateway Network (GAN) is the backbone of Ignition redundancy and scaleout. By default, port `8060` is accessible within the namespace. You can harden this using **NetworkPolicies**.

### Enabling Isolation

Setting `networkPolicy.enabled: true` creates a policy that:

1. Allows HTTP/HTTPS traffic from any pod (for user access).
2. **Restricts** port `8060` (GAN) traffic to only pods that carry the `app.kubernetes.io/name` label matching your Ignition deployment.

```yaml
ignition:
  networkPolicy:
    enabled: true
```

---

## 5. Graceful Shutdown

Kubernetes can terminate pods abruptly. Ignition benefits from a clean shutdown to ensure the internal SQLite configuration database is flushed to disk correctly.

The charts automatically include a `preStop` hook that executes `/config/scripts/shutdown.sh`. This script sends a shutdown signal to the gateway process, giving it time to exit cleanly before the container is killed.

> **Note**: Ensure your `terminationGracePeriodSeconds` (default: 60) is long enough for your gateway to shut down completely.

---

## 6. Service Connectivity & GitOps

In environments managed by GitOps tools like **ArgoCD**, service reachability during rolling updates is critical.

### Session Affinity

By default, `ignition.service.sessionAffinity` is set to `None`.

In earlier versions, this was set to `ClientIP` to support sticky sessions for Vision/Perspective. However, this can cause pods to become unreachable via the Service during a `RollingUpdate` if the client holds a stale affinity mapping to a terminating pod.

If your infrastructure (e.g., an external LoadBalancer) handles stickiness, keep this as `None`. If you must use `ClientIP`, be aware that clients may experience brief connection drops during gateway restarts as the mapping table is cleared.

### Stable Pod Identity (Headless Services)

StatefulSets require a **Headless Service** to maintain stable network identities. The charts now automatically create a `-headless` service (e.g., `ignition-failover-headless`) which is used as the `serviceName` for the StatefulSet.

This ensures that pods are reachable at:
`<pod-name>.<release-name>-headless.<namespace>.svc.cluster.local`

This is internal architectural logic and does not replace the standard ClusterIP/NodePort/LoadBalancer service used for external traffic.
