---
title: Upgrading
order: 5
description: Upgrade an existing installation to a newer chart version.
---

This guide covers upgrading an installed chart, including the one-time steps for installs from 4.0.0 or earlier.

Most upgrades are a plain `helm upgrade` after `helm repo update`. Read the chart's `CHANGELOG.md` for the versions you are skipping. The StatefulSets replace one pod at a time, the Backup (pod 1) before the Master (pod 0), and a Backup only counts as Ready once it is running.

Upgrading from **4.0.0 or earlier** (including 3.x) needs the extra steps below, once.

## 1. Let the StatefulSets be recreated

From 4.1.0 each StatefulSet is governed by a `<name>-headless` Service. Kubernetes does not allow `serviceName` to change on an existing StatefulSet, so `helm upgrade` is rejected. Delete only the StatefulSet objects first. Their pods and volumes keep running, and the upgraded StatefulSets adopt them:

```bash
# failover
kubectl delete statefulset ignition-failover --cascade=orphan -n <namespace>
# scaleout
kubectl delete statefulset ignition-scaleout-frontend ignition-scaleout-backend --cascade=orphan -n <namespace>

helm upgrade <release> ignition-charts/<chart> -n <namespace> ...
```

The StatefulSet names above assume the default `applicationName`; use your own if you set it.

On start, the upgraded gateways apply the chart's redundancy settings to their volumes, including the peer address under the new Service name, so a pair reconnects once both pods have been replaced.

## 2. Turn on active routing afterwards

If you want `activeRouting`, enable it in a **second** upgrade, after every pod has been replaced. Until the Master's pod is replaced it can only be reached under the old Service name, so the new Backup cannot sync with it. With `activeRouting` a Backup must be in sync to be Ready, so a single upgrade that does both would wait indefinitely (the Master keeps serving meanwhile).

## 3. Volumes from 3.x installs that ran as root

Charts up to 3.1.0 ran the gateway as root by default. On storage that does not apply `fsGroup` (for example local-path), those data volumes are owned by root, and the upgraded gateway, which runs as user 2003, cannot update them: its `preconfigure` init container fails with `Permission denied`.

If your 3.x install did not set `securityContext.runAsUser`, add this for the upgrade and remove it again once the pods are running:

```yaml
ignition:
  fixDataOwnership: true   # scaleout: frontend.fixDataOwnership and backend.fixDataOwnership
```

It adds an init container that chowns the volume as root (with only the `CHOWN`, `DAC_OVERRIDE` and `FOWNER` capabilities), so the namespace must allow the baseline Pod Security level while it is on.

## 4. Let your traffic through the NetworkPolicy

Charts up to 4.0.0 created no NetworkPolicy. The current charts create one by default, and it admits web traffic only from pods in the release's namespace. So the upgrade cuts off traffic that reaches the gateways through a NodePort or LoadBalancer Service, an ingress controller in another namespace, or Prometheus, unless you allow it **in the same upgrade**. Add a rule for each of those, as the [examples](https://github.com/Apollogeddon/ignition-helm/tree/main/examples) do:

```yaml
ignition:                  # scaleout: frontend (and backend, if reached from outside)
  networkPolicy:
    extraIngress:
      - from:
          # an ingress controller or Prometheus: its namespace
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: ingress-nginx
          # a NodePort or LoadBalancer Service: the nodes' (or your clients') addresses
          - ipBlock:
              cidr: 10.0.0.0/8
        ports:
          - {protocol: TCP, port: 8088}
          - {protocol: TCP, port: 8043}
```

Or keep the old behaviour with `networkPolicy.enabled: false` (`ignition.networkPolicy` in failover, `frontend.networkPolicy` and `backend.networkPolicy` in scaleout). See [Network security](../advanced-config/#network-security-gateway-network-isolation).

## Chart 4.1.0

4.1.0 has been withdrawn. Its pods ran `gwcmd.sh -p` as a shutdown hook, which resets the gateway login password whenever a pod stops. Upgrade from 4.0.0 or earlier straight to a later version.
