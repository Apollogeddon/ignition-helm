---
title: ignition-scaleout
description: A Helm chart for failover Ignition Gateway with scalable frontend client functionality
---

A Helm chart for failover Ignition Gateway with scalable frontend client functionality. This chart deploys separate backend (controller) and frontend (agent) sets of Ignition Gateways to support high-scale architectures.

## Configuration

The following sections list the configurable parameters of the ignition-scaleout chart.

### General Settings

Global settings applicable to the entire chart.

| Parameter | Type | Default |
|-----------|------|---------|
| `applicationName` | string | `"ignition-scaleout"` |
| `image.repository` | string | `"inductiveautomation/ignition"` |
| `image.tag` | string | `"8.3"` |
| `image.pullPolicy` | string | `"IfNotPresent"` |
| `affinity.enabled` | bool | `false` |
| `affinity.topologyKey` | string | `"kubernetes.io/hostname"` |
| `certManager.issuer.name` | string | `"cluster-issuer"` |
| `certManager.issuer.kind` | string | `"ClusterIssuer"` |
| `serviceAccount.create` | bool | `false` |
| `serviceAccount.name` | string | `""` |
| `serviceAccount.annotations` | object | `{}` |

### Backend Configuration

The Backend acts as the controller and primary data processor.

#### Ignition Settings (Backend)

| Parameter | Type | Default |
|-----------|------|---------|
| `backend.config` | object | *(See below)* |
| `backend.args` | list | *(See below)* |
| `backend.logging.level` | string | `"INFO"` |
| `backend.eam.role` | string | `"Controller"` |
| `backend.spoofMachineId` | string | `""` |
| `backend.tls.keystorePassword` | string | `"ignition"` |
| `backend.gan.keystorePassword` | string | `"metro"` |

**Default `backend.config`:**

```yaml
ACCEPT_IGNITION_EULA: "Y"
DISABLE_QUICKSTART: "true"
GATEWAY_ADMIN_USERNAME: "admin"
GATEWAY_MODULES_ENABLED: "alarm-notification,modbus-driver-v2,opc-ua,reporting,siemens-drivers,sql-bridge,tag-historian,udp-tcp-drivers"
GATEWAY_NETWORK_REQUIRETWOWAYAUTH: "true"
GATEWAY_NETWORK_SECURITYPOLICY: "Unrestricted"
IGNITION_EDITION: "standard"
```

**Default `backend.args`:**

```yaml
- "-m"
- "1024"
- "-n"
- "$(GATEWAY_SYSTEM_NAME)"
- "--"
- "gateway.useProxyForwardedHeader=true"
```

#### Redundancy (Backend)

| Parameter | Type | Default |
|-----------|------|---------|
| `backend.redundancy.enabled` | bool | `false` |
| `backend.redundancy` | object | *(See below)* |

**Default `backend.redundancy`:**

```yaml
backupFailoverTimeout: 10000
enableSsl: true
enabled: false
httpConnectTimeout: 10000
httpReadTimeout: 60000
joinWaitTime: 30000
masterRecoveryMode: "Automatic"
maxDiskMb: 100
pingMaxMissed: 10
pingRate: 1000
pingTimeout: 300
syncTimeoutSecs: 60
websocketTimeout: 10000
```

#### Persistence (Backend)

| Parameter | Type | Default |
|-----------|------|---------|
| `backend.persistence.size` | string | `"3Gi"` |
| `backend.persistence.accessModes` | list | `["ReadWriteOnce"]` |
| `backend.persistence.storageClassName` | string | `""` |
| `backend.localMounts` | list | `[]` |
| `backend.restore.enabled` | bool | `false` |
| `backend.restore.url` | string | `""` |

#### Networking (Backend)

| Parameter | Type | Default |
|-----------|------|---------|
| `backend.service.type` | string | `"NodePort"` |
| `backend.service.ports` | object | `{"gan":8060,"http":8088,"https":8043}` |
| `backend.service.sessionAffinity` | string | `"ClientIP"` |
| `backend.ingress.enabled` | bool | `false` |
| `backend.ingress.tls` | list | `[]` |

#### Resources & Security (Backend)

| Parameter | Type | Default |
|-----------|------|---------|
| `backend.resources.requests` | object | `{"cpu":"500m","memory":"1Gi"}` |
| `backend.resources.limits.cpu` | string | `"1000m"` |
| `backend.resources.limits.memory` | string | `"2Gi"` |
| `backend.securityContext` | object | `{"fsGroup":2003,"runAsGroup":2003,"runAsNonRoot":true,"runAsUser":2003}` |
| `backend.secrets` | object | `{"GATEWAY_ADMIN_PASSWORD":"admin"}` |
| `backend.sealedSecrets` | bool | `false` |

#### Probes (Backend)

| Parameter | Type | Default |
|-----------|------|---------|
| `backend.livenessProbe` | object | *(See below)* |
| `backend.readinessProbe` | object | *(See below)* |

**Default `backend.livenessProbe`:**

```yaml
command: ["health-check.sh", "-t", "5"]
enabled: true
failureThreshold: 3
initialDelaySeconds: 120
periodSeconds: 10
timeoutSeconds: 5
```

**Default `backend.readinessProbe`:**

```yaml
command: ["health-check.sh", "-t", "3"]
enabled: true
failureThreshold: 10
initialDelaySeconds: 60
periodSeconds: 5
timeoutSeconds: 3
```

### Frontend Configuration

The Frontend acts as the agent, serving client sessions (Perspective, Vision).

#### Ignition Settings (Frontend)

| Parameter | Type | Default |
|-----------|------|---------|
| `frontend.config` | object | *(See below)* |
| `frontend.args` | list | *(See below)* |
| `frontend.logging.level` | string | `"INFO"` |
| `frontend.eam.role` | string | `"Agent"` |
| `frontend.spoofMachineId` | string | `""` |
| `frontend.tls.keystorePassword` | string | `"ignition"` |
| `frontend.gan.keystorePassword` | string | `"metro"` |

**Default `frontend.config`:**

```yaml
ACCEPT_IGNITION_EULA: "Y"
DISABLE_QUICKSTART: "true"
GATEWAY_ADMIN_USERNAME: "admin"
GATEWAY_MODULES_ENABLED: "perspective,symbol-factory"
GATEWAY_NETWORK_REQUIRETWOWAYAUTH: "true"
GATEWAY_NETWORK_SECURITYPOLICY: "Unrestricted"
IGNITION_EDITION: "standard"
```

**Default `frontend.args`:**

```yaml
- "-m"
- "1024"
- "-n"
- "$(GATEWAY_SYSTEM_NAME)"
- "--"
- "gateway.useProxyForwardedHeader=true"
```

#### Scaling & Redundancy (Frontend)

| Parameter | Type | Default |
|-----------|------|---------|
| `frontend.redundancy.replicas` | int | `1` |
| `frontend.redundancy` | object | `{"replicas":1}` |

#### Networking (Frontend)

| Parameter | Type | Default |
|-----------|------|---------|
| `frontend.service.type` | string | `"NodePort"` |
| `frontend.service.ports` | object | `{"gan":8060,"http":8088,"https":8043}` |
| `frontend.service.sessionAffinity` | string | `"ClientIP"` |
| `frontend.ingress.enabled` | bool | `false` |
| `frontend.ingress.tls` | list | `[]` |

#### Resources & Security (Frontend)

| Parameter | Type | Default |
|-----------|------|---------|
| `frontend.resources.requests` | object | `{"cpu":"500m","memory":"1Gi"}` |
| `frontend.resources.limits.cpu` | string | `"1000m"` |
| `frontend.resources.limits.memory` | string | `"2Gi"` |
| `frontend.localMounts` | list | `[]` |
| `frontend.securityContext` | object | `{"fsGroup":2003,"runAsGroup":2003,"runAsNonRoot":true,"runAsUser":2003}` |
| `frontend.secrets` | object | `{"GATEWAY_ADMIN_PASSWORD":"admin"}` |
| `frontend.sealedSecrets` | bool | `false` |

#### Probes (Frontend)

| Parameter | Type | Default |
|-----------|------|---------|
| `frontend.livenessProbe` | object | *(See below)* |
| `frontend.readinessProbe` | object | *(See below)* |

**Default `frontend.livenessProbe`:**

```yaml
command: ["health-check.sh", "-t", "5"]
enabled: true
failureThreshold: 3
initialDelaySeconds: 120
periodSeconds: 10
timeoutSeconds: 5
```

**Default `frontend.readinessProbe`:**

```yaml
command: ["health-check.sh", "-t", "3"]
enabled: true
failureThreshold: 10
initialDelaySeconds: 15
periodSeconds: 5
timeoutSeconds: 3
```
