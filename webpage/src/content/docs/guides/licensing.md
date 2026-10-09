---
title: Licensing
order: 6
description: How to license Ignition gateways running in Kubernetes.
---

This page explains why traditional Ignition licenses fit containers poorly and which licensing method to use with these charts. The charts do not manage licenses themselves; you activate them on each gateway as you would outside Kubernetes.

Traditional Ignition licenses are tied to the gateway's machine ID, and a container's machine ID can change whenever the pod is recreated. That makes them a poor fit for pods that Kubernetes reschedules.

## Leased licensing

Leased licensing is the recommended method for Kubernetes. It does not depend on a fixed machine ID: the gateway checks out a lease from Inductive Automation's licensing server (or your own on-premises license server) instead.

For Kubernetes this means:

* **Resilience**: a rescheduled or recreated pod checks out a new lease.
* **Flexibility**: you can add frontend gateways without tracking individual machine IDs.
* **No manual reactivation**: a restarted pod does not need its license activated again.

## Frontend licensing (scaleout)

In the scaleout architecture, frontend gateways have no persistent volume and can be added or removed at any time. Leased licensing lets you scale them, including with a HorizontalPodAutoscaler, while each gateway manages its own lease.
