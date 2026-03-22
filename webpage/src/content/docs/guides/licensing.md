---
title: Licencing
description: Managing Ignition licencing in Kubernetes.
---

One of the challenges with running Ignition in containers is that the **Machine ID**—which traditional licence keys are tied to—changes every time the container is recreated.

For dynamic environments like Kubernetes, **Leased Licencing** is the recommended method.

## Leased Licencing

Leased Licencing (using an 8-character Licence Key) is the preferred method for Kubernetes deployments. It does not rely on a static Machine ID; instead, it checks out a licence session from the Inductive Automation licence server (or an on-premise Licence Server).

### Benefits for Kubernetes

* **Resilience**: If a pod is rescheduled or recreated, it simply checks out a new session.
* **Flexibility**: Easily scale Frontend nodes without worrying about individual Machine IDs.
* **Automation**: No manual intervention is required to "re-activate" a licence after a pod restart.

## Frontend Licensing (Scaleout)

In a **Scaleout** architecture, Frontend nodes are often designed to be ephemeral. Using Leased Licencing allows these nodes to be horizontally scaled (via HPA) while automatically managing their licence state.
