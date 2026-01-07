---
title: Architecture
description: Understanding the deployment models.
---

## Overview

This repository provides two primary architectures for deploying Ignition on Kubernetes.

### 1. Failover (Master/Backup)

The `ignition-failover` chart deploys a standard redundant pair of Ignition gateways.

* **Replicas**: 2 (Fixed)
* **State**: StatefulSet with stable network identities.
* **Networking**:
  * `0`: Master (Primary)
  * `1`: Backup (Redundant)
* **Use Case**: Standard SCADA deployments requiring high availability.

```mermaid
graph TD
    User((User/Device)) --> Ingress
    Ingress --> Service
    subgraph K8s Cluster
        Service --> Pod0[Ignition-0: Master ]
        Service -.-> Pod1[Ignition-1: Backup ]
        Pod0 <-->|Gateway Network| Pod1
    end
```

### 2. Scaleout (Frontend/Backend)

The `ignition-scaleout` chart separates the workload into two distinct StatefulSets:

* **Backend**: Handles device connections, database logging, and tag history.
* **Frontend**: Handles Perspective sessions and API requests.

This architecture allows you to scale the Frontend layer independently of the Backend layer to handle massive user loads.

```mermaid
graph TD
    User((User)) --> LB[Load Balancer]
    subgraph Frontend Layer
        LB --> FE1[Frontend-0]
        LB --> FE2[Frontend-1]
        LB --> FE3[Frontend-2]
    end
    subgraph Backend Layer
        FE1 -->|GAN| BE[Backend: Master/Backup]
        FE2 -->|GAN| BE
        FE3 -->|GAN| BE
        Device((PLC/Device)) --> BE
    end
```
