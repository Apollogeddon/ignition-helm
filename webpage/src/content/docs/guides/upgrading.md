---
title: Upgrading
order: 5
description: Upgrade an existing installation to a newer chart version.
---

This guide covers upgrading an installed chart, and the one-time steps some installs need.

Most upgrades are a plain `helm upgrade` after `helm repo update`. Read the chart's `CHANGELOG.md` for the versions you are skipping. The StatefulSets replace one pod at a time, the Backup (pod 1) before the Master (pod 0), and a Backup only counts as Ready once it is running.

Check these before you upgrade, and take each step that applies to your install.

## If your StatefulSets name another Service

Each StatefulSet is governed by a `<name>-headless` Service (`<name>-frontend-headless` and `<name>-backend-headless` in scaleout). Check what yours name:

```bash
kubectl get statefulset -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.serviceName}{"\n"}{end}'
```

Kubernetes does not allow `serviceName` to change on an existing StatefulSet, so if one names another Service, `helm upgrade` is rejected. Delete only the StatefulSet objects first. Their pods and volumes keep running, and the upgraded StatefulSets adopt them:

```bash
# failover
kubectl delete statefulset ignition-failover --cascade=orphan -n <namespace>
# scaleout
kubectl delete statefulset ignition-scaleout-frontend ignition-scaleout-backend --cascade=orphan -n <namespace>

helm upgrade <release> ignition-charts/<chart> -n <namespace> ...
```

The StatefulSet names above assume the default `applicationName`; use your own if you set it.

On start, the gateways apply the chart's redundancy settings to their volumes, including the peer address under the `-headless` Service's name, so a pair reconnects once both pods have been replaced.

If you want `activeRouting` too, enable it in a **second** upgrade, after every pod has been replaced. Until the Master's pod is replaced it can only be reached under the other Service's name, so the new Backup cannot sync with it. With `activeRouting` a Backup must be in sync to be Ready, so a single upgrade that does both would wait indefinitely (the Master keeps serving meanwhile).

## If your data volumes are owned by root

The gateways run as user 2003. On storage that does not apply `fsGroup` (for example local-path), a data volume a gateway running as root wrote is owned by root, and the gateway cannot update it: its `preconfigure` init container fails with `Permission denied`. If your install ran the gateway as root, add this for the upgrade and remove it again once the pods are running:

```yaml
ignition:
  fixDataOwnership: true   # scaleout: frontend.fixDataOwnership and backend.fixDataOwnership
```

It adds an init container that chowns the volume as root (with only the `CHOWN`, `DAC_OVERRIDE` and `FOWNER` capabilities), so the namespace must allow the baseline Pod Security level while it is on.

## If traffic reaches the gateways from outside the namespace

The charts create a NetworkPolicy by default, and it admits web traffic only from pods in the release's namespace. If your release has no NetworkPolicy from the chart yet, the upgrade cuts off traffic that reaches the gateways through a NodePort or LoadBalancer Service, an ingress controller in another namespace, or Prometheus, unless you allow it **in the same upgrade**. Add a rule for each of those, as the [examples](https://github.com/Apollogeddon/ignition-helm/tree/main/examples) do:

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

Or turn the NetworkPolicy off with `networkPolicy.enabled: false` (`ignition.networkPolicy` in failover, `frontend.networkPolicy` and `backend.networkPolicy` in scaleout). See [Network security](../advanced-config/#network-security-gateway-network-isolation).

## If other gateways join yours with your own CA

Each gateway trusts only its release's own Gateway Network CA, not the root of the issuer that signed it. With the default self-signed issuer the two are the same certificate. With your own CA issuer (`certManager.issuer.name`), a gateway outside the release whose certificate that issuer signs, such as another release or an external gateway, is refused on the Gateway Network. Give each such peer trust explicitly in the gateway's Gateway Network settings. An issuer that publishes no `ca.crt` (for example ACME) works too.

## If you use SealedSecrets

Each Gateway Network keystore takes its password from the release's own secrets (`<name>-secrets`, or `<name>-frontend-secrets` and `<name>-backend-secrets`), and the chart refuses a value in `secrets` that isn't sealed, the defaults included. If your release has a separate `<name>-gan-metro-keystore` Secret, the upgrade deletes it, and the keystore keeps the password from that Secret until cert-manager next issues the certificate. Once the upgrade has rendered, renew it (`cmctl renew <name>-gan`, or `<name>-frontend-gan` and `<name>-backend-gan`).

## If you autoscale the scaleout frontend

`frontend.hpa.enabled` needs `componentSelectors: true`, as without it the autoscaler also counts the backend's pods, and the chart fails to render. If your StatefulSets use the shared selector (`componentSelectors: false`), setting it changes both StatefulSets' selectors, which Kubernetes doesn't allow on an existing object. Delete only the StatefulSet objects first; the upgraded StatefulSets adopt the running pods:

```bash
kubectl delete statefulset <name>-frontend <name>-backend -n <namespace> --cascade=orphan
helm upgrade <release> ignition-charts/ignition-scaleout -n <namespace> ... --set componentSelectors=true
```

The recreated frontend StatefulSet starts at one gateway until the autoscaler raises it to `minReplicas`, so upgrade in a quiet period.
