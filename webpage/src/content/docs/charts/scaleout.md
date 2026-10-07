---
title: ignition-scaleout
description: A Helm chart for failover Ignition Gateway with scalable frontend client functionality
---

A Helm chart for failover Ignition Gateway with scalable frontend client functionality. This chart deploys separate backend (controller) and frontend (agent) sets of Ignition Gateways to support high-scale architectures.

## Initialization Process

The following diagram illustrates how the chart initializes the distributed architecture, establishing trust and connectivity between the Frontend and Backend layers.

> **Note:** The Backend StatefulSet includes two headless services (`-backend-primary` and `-backend-backup`) targeting specific nodes for direct diagnostics.

```mermaid
sequenceDiagram
    participant K8s as Kubernetes
    participant Certs as Cert Manager
    participant Backend as Backend (Controller)
    participant Frontend as Frontend (Agent)
    
    par Backend Initialization
        K8s->>Backend: Start Pod
        Backend->>Certs: Request GAN Certs
        Certs-->>Backend: Mount Secrets (TLS/CA)
        Backend->>Backend: Initialize as Controller
    and Frontend Initialization
        K8s->>Frontend: Start Pod
        Frontend->>Certs: Request GAN Certs
        Certs-->>Frontend: Mount Secrets (TLS/CA)
        Frontend->>Frontend: Initialize as Agent
    end
    
    Frontend->>Backend: Open GAN Connection (Mutual TLS)
    Backend-->>Frontend: Accept Connection
    Frontend->>Frontend: Mount Proxy Tags & Projects
```

> **Upgrading from 4.0.0 or earlier?** It needs a one-time step; see the [Upgrading guide](../../guides/upgrading/).

## Configuration

The following sections list the configurable parameters of the ignition-scaleout chart.

### General Settings

Global settings applicable to the entire chart.

| Parameter | Type | Default |
| --- | --- | --- |
| `applicationName` | string | `"ignition-scaleout"` |
| `image.repository` | string | `"inductiveautomation/ignition"` |
| `image.tag` | string | `""` |
| `image.pullPolicy` | string | `"IfNotPresent"` |
| `affinity.enabled` | bool | `false` |
| `affinity.topologyKey` | string | `"kubernetes.io/hostname"` |
| `certManager.issuer.name` | string | `"cluster-issuer"` |
| `certManager.issuer.kind` | string | `"ClusterIssuer"` |
| `certManager.rotation.enabled` | bool | `false` |
| `certManager.rotation.schedule` | string | `"0 7 * * *"` |
| `certManager.restartOnRenewal` | object | `{"enabled":false,"schedule":"*/15 * * * *","image":"alpine/kubectl:1.34.1"}` |
| `serviceAccount.create` | bool | `false` |
| `serviceAccount.name` | string | `""` |
| `serviceAccount.annotations` | object | `{}` |

### Backend Configuration

The Backend acts as the controller and primary data processor.

#### Ignition Settings (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.config` | object | *(See below)* |
| `backend.args` | list | *(See below)* |
| `backend.logging.level` | string | `"INFO"` |
| `backend.logging.wrapperLogToStdout` | bool | `true` |
| `backend.logging.loggers` | object | `{}` |
| `backend.logging.sqlite` | object | `{}` |
| `backend.eam.role` | string | `"Controller"` |

**Default `backend.config`:**

```yaml
IGNITION_EDITION: standard
ACCEPT_IGNITION_EULA: "Y"
DISABLE_QUICKSTART: "true"
GATEWAY_NETWORK_SECURITYPOLICY: Unrestricted
GATEWAY_NETWORK_REQUIRETWOWAYAUTH: "true"
GATEWAY_MODULES_ENABLED: alarm-notification,modbus-driver-v2,opc-ua,reporting,siemens-drivers,sql-bridge,tag-historian,udp-tcp-drivers
```

**Default `backend.args`:**

```yaml
- "-m"
- "1024"
- "-n"
- $(GATEWAY_SYSTEM_NAME)
- "--"
- gateway.useProxyForwardedHeader=true
```

#### Web Server SSL/TLS (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.ssl.enabled` | bool | `false` |
| `backend.ssl.secretName` | string | `""` |

#### Security & Monitoring (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.networkPolicy.enabled` | bool | `true` |
| `backend.networkPolicy.extraIngress` | list | `[]` |
| `backend.serviceMonitor.enabled` | bool | `false` |
| `backend.serviceMonitor.interval` | string | `"30s"` |

#### Redundancy (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.redundancy.enabled` | bool | `false` |
| `backend.redundancy` | object | *(See below)* |
| `backend.activeRouting` | object | `{"enabled":false,"image":"alpine/kubectl:1.34.1","intervalSeconds":2,"unknownHold":3,"resources":{"requests":{"cpu":"10m","memory":"32Mi"},"limits":{"cpu":"200m","memory":"128Mi"}}}` |

**Default `backend.redundancy`:**

```yaml
enabled: false
pingRate: 1000
pingTimeout: 300
pingMaxMissed: 10
enableSsl: true
joinWaitTime: 30000
websocketTimeout: 10000
syncTimeoutSecs: 60
maxDiskMb: 100
masterRecoveryMode: Automatic
httpConnectTimeout: 10000
httpReadTimeout: 60000
backupFailoverTimeout: 10000
```

#### Persistence (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.persistence.size` | string | `"3Gi"` |
| `backend.persistence.accessModes` | list | `["ReadWriteOnce"]` |
| `backend.persistence.storageClassName` | string | `""` |
| `backend.localMounts` | list | `[]` |
| `backend.restore.enabled` | bool | `false` |
| `backend.restore.url` | string | `""` |
| `backend.emptyDirSizeLimit` | object | `{"logs":"","temp":"","dotIgnition":""}` |
| `backend.fixDataOwnership` | bool | `false` |

#### Networking (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.service.type` | string | `"NodePort"` |
| `backend.service.ports` | object | `{"http":8088,"https":8043,"gan":8060}` |
| `backend.service.nodePorts` | object | unset |
| `backend.service.sessionAffinity` | string | `"None"` |
| `backend.ingress.enabled` | bool | `false` |
| `backend.ingress.className` | string | `""` |
| `backend.ingress.tls` | list | `[]` |

#### Resources & Security (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.resources.requests` | object | `{"memory":"1Gi","cpu":"500m"}` |
| `backend.resources.limits.cpu` | string | `"1000m"` |
| `backend.resources.limits.memory` | string | `"2Gi"` |
| `backend.securityContext` | object | `{"runAsUser":2003,"runAsGroup":2003,"fsGroup":2003,"runAsNonRoot":true}` |
| `backend.secrets` | object | `{"GATEWAY_ADMIN_USERNAME":"admin","GATEWAY_ADMIN_PASSWORD":"admin","IGNITION_GAN_KEYSTORE_PASSWORD":"metro","IGNITION_WEB_KEYSTORE_PASSWORD":"ignition"}` |
| `backend.sealedSecrets` | bool | `false` |

#### Probes (Backend)

| Parameter | Type | Default |
| --- | --- | --- |
| `backend.livenessProbe` | object | *(See below)* |
| `backend.readinessProbe` | object | *(See below)* |
| `backend.startupProbe` | object | `{"enabled":false,"initialDelaySeconds":30,"periodSeconds":10,"failureThreshold":30,"timeoutSeconds":5,"command":["/config/scripts/health-check.sh","-t","5"]}` |
| `backend.lifecycle` | object | `{}` |

**Default `backend.livenessProbe`:**

```yaml
enabled: true
initialDelaySeconds: 120
periodSeconds: 10
failureThreshold: 3
timeoutSeconds: 5
command:
  - /config/scripts/health-check.sh
  - "-t"
  - "5"
```

**Default `backend.readinessProbe`:**

```yaml
enabled: true
initialDelaySeconds: 120
periodSeconds: 5
failureThreshold: 10
timeoutSeconds: 3
command:
  - /config/scripts/health-check.sh
  - "-t"
  - "3"
  - "-r"
```

### Frontend Configuration

The Frontend acts as the agent, serving client sessions (Perspective, Vision).

#### Ignition Settings (Frontend)

| Parameter | Type | Default |
| --- | --- | --- |
| `frontend.config` | object | *(See below)* |
| `frontend.args` | list | *(See below)* |
| `frontend.logging.level` | string | `"INFO"` |
| `frontend.logging.wrapperLogToStdout` | bool | `true` |
| `frontend.logging.loggers` | object | `{}` |
| `frontend.logging.sqlite` | object | `{}` |
| `frontend.eam.role` | string | `"Agent"` |

**Default `frontend.config`:**

```yaml
IGNITION_EDITION: standard
ACCEPT_IGNITION_EULA: "Y"
DISABLE_QUICKSTART: "true"
GATEWAY_NETWORK_SECURITYPOLICY: Unrestricted
GATEWAY_NETWORK_REQUIRETWOWAYAUTH: "true"
GATEWAY_MODULES_ENABLED: perspective,symbol-factory
```

**Default `frontend.args`:**

```yaml
- "-m"
- "1024"
- "-n"
- $(GATEWAY_SYSTEM_NAME)
- "--"
- gateway.useProxyForwardedHeader=true
```

#### Web Server SSL/TLS (Frontend)

| Parameter | Type | Default |
| --- | --- | --- |
| `frontend.ssl.enabled` | bool | `false` |
| `frontend.ssl.secretName` | string | `""` |

#### Security & Monitoring (Frontend)

| Parameter | Type | Default |
| --- | --- | --- |
| `frontend.networkPolicy.enabled` | bool | `true` |
| `frontend.networkPolicy.extraIngress` | list | `[]` |
| `frontend.serviceMonitor.enabled` | bool | `false` |
| `frontend.serviceMonitor.interval` | string | `"30s"` |

#### Scaling & HPA (Frontend)

| Parameter | Type | Default |
| --- | --- | --- |
| `frontend.redundancy.replicas` | int | `1` |
| `frontend.hpa.enabled` | bool | `false` |
| `frontend.hpa.minReplicas` | int | `1` |
| `frontend.hpa.maxReplicas` | int | `10` |
| `frontend.hpa.targetCPUUtilizationPercentage` | int | `80` |

#### Networking (Frontend)

| Parameter | Type | Default |
| --- | --- | --- |
| `frontend.service.type` | string | `"NodePort"` |
| `frontend.service.ports` | object | `{"http":8088,"https":8043,"gan":8060}` |
| `frontend.service.nodePorts` | object | unset |
| `frontend.service.sessionAffinity` | string | `"None"` |
| `frontend.ingress.enabled` | bool | `false` |
| `frontend.ingress.className` | string | `""` |
| `frontend.ingress.tls` | list | `[]` |

#### Resources & Security (Frontend)

| Parameter | Type | Default |
| --- | --- | --- |
| `frontend.resources.requests` | object | `{"memory":"1Gi","cpu":"500m"}` |
| `frontend.resources.limits.cpu` | string | `"1000m"` |
| `frontend.resources.limits.memory` | string | `"2Gi"` |
| `frontend.localMounts` | list | `[]` |
| `frontend.emptyDirSizeLimit` | object | `{"logs":"","temp":"","dotIgnition":""}` |
| `frontend.fixDataOwnership` | bool | `false` |
| `frontend.securityContext` | object | `{"runAsUser":2003,"runAsGroup":2003,"fsGroup":2003,"runAsNonRoot":true}` |
| `frontend.secrets` | object | `{"GATEWAY_ADMIN_USERNAME":"admin","GATEWAY_ADMIN_PASSWORD":"admin","IGNITION_GAN_KEYSTORE_PASSWORD":"metro","IGNITION_WEB_KEYSTORE_PASSWORD":"ignition"}` |
| `frontend.sealedSecrets` | bool | `false` |

#### Probes (Frontend)

| Parameter | Type | Default |
| --- | --- | --- |
| `frontend.livenessProbe` | object | *(See below)* |
| `frontend.readinessProbe` | object | *(See below)* |
| `frontend.startupProbe` | object | `{"enabled":false,"initialDelaySeconds":30,"periodSeconds":10,"failureThreshold":30,"timeoutSeconds":5,"command":["/config/scripts/health-check.sh","-t","5"]}` |
| `frontend.lifecycle` | object | `{}` |

**Default `frontend.livenessProbe`:**

```yaml
enabled: true
initialDelaySeconds: 120
periodSeconds: 10
failureThreshold: 3
timeoutSeconds: 5
command:
  - /config/scripts/health-check.sh
  - "-t"
  - "5"
```

**Default `frontend.readinessProbe`:**

```yaml
enabled: true
initialDelaySeconds: 15
periodSeconds: 5
failureThreshold: 10
timeoutSeconds: 3
command:
  - /config/scripts/health-check.sh
  - "-t"
  - "3"
  - "-r"
```
