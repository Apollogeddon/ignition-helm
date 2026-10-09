---
title: Advanced configuration
order: 4
description: Configuration patterns for production Ignition deployments.
---

This guide covers configuration patterns for running the charts in production: database credentials, monitoring, scaling, network security, shutdown and Service behavior.

## Database credentials

You can configure database connections in the Gateway web UI, but managing the connection details in Kubernetes keeps them with the rest of your deployment configuration.

### Environment variables

Pass database connection details to the gateway with the `config` and `secrets` maps. The chart renders them as a ConfigMap and a Secret, and both become environment variables in the gateway container.

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

In the Gateway web UI (or your `.gwbk` backup), you can then reference these values as `${DB_HOST}`, `${DB_USER}` and so on in the database connection settings.

## Monitoring

For production, use the Prometheus Operator to collect metrics.

### Prerequisites

1. **A metrics endpoint**: the gateway must expose metrics in Prometheus format. The OpenTelemetry Java agent covers the JVM; a WebDev script can publish tag values.
2. **The Prometheus Operator** running in your cluster.

### Enable scraping

Enable the `serviceMonitor` so Prometheus discovers and scrapes the gateways:

```yaml
ignition:
  serviceMonitor:
    enabled: true
    interval: "15s"
    path: "/data/metrics" # Match the path of your chosen exporter
```

## Horizontal scaling (scaleout)

The scaleout chart lets you scale the frontend gateways independently, which suits Perspective-heavy applications where session load varies.

### Configure the autoscaler

The `ignition-scaleout` chart can create a HorizontalPodAutoscaler for the frontend:

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

### Why scale on CPU

Perspective sessions run on the frontend gateways, and each active session uses CPU for scripts and binding evaluation. Scaling on CPU utilization adds frontend gateways before the existing ones slow down.

## Network security (Gateway Network isolation)

The Gateway Network carries Ignition redundancy and scaleout traffic. The charts create a NetworkPolicy for it by default (`networkPolicy.enabled: true`) that:

1. Allows HTTP and HTTPS traffic from any pod in the namespace.
2. Allows Gateway Network traffic (port `8060`) only from pods whose `app.kubernetes.io/name` label matches the chart's `applicationName`.
3. Blocks other ingress to the gateways. Add rules with `networkPolicy.extraIngress`, for example for your ingress controller's namespace or for node CIDRs when you use NodePort or LoadBalancer Services.

```yaml
ignition:
  networkPolicy:
    enabled: true
```

## Graceful shutdown

When Kubernetes stops a pod it sends the gateway `SIGTERM`, and Ignition shuts down cleanly on its own, flushing its internal configuration database. The charts therefore add no `preStop` hook by default.

> **Warning**: do not use `gwcmd.sh -p` as a shutdown hook. Chart 4.1.0 did, and that command resets the gateway login password (on Ignition 8.1 and 8.3) every time a pod stops. 4.1.0 has been withdrawn.

If you need your own hooks, set `ignition.lifecycle` (rendered as-is). The pods' `terminationGracePeriodSeconds` is 60; make sure your hooks and the gateway's shutdown finish within it.

## Services and GitOps

With GitOps tools such as Argo CD, Services must stay reachable through rolling updates.

### Session affinity

`ignition.service.sessionAffinity` defaults to `None`.

Earlier versions set it to `ClientIP` for sticky Vision and Perspective sessions. That can leave a client unable to reach the Service during a rolling update while it holds an affinity mapping to a terminating pod.

If your infrastructure (for example an external load balancer) handles stickiness, keep it as `None`. If you use `ClientIP`, expect brief connection drops while gateways restart.

### Headless Services

A StatefulSet needs a headless Service to give its pods stable network identities. The charts create a `<name>-headless` Service (for example `ignition-failover-headless`), used as the StatefulSet's `serviceName`. Pods are reachable at:

`<pod-name>.<name>-headless.<namespace>.svc.cluster.local`

where `<name>` is `applicationName`, with `-frontend` or `-backend` appended in the scaleout chart. This Service is for in-cluster identity; external traffic still uses the main ClusterIP, NodePort or LoadBalancer Service.
