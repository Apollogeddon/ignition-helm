---
title: Upgrading
order: 5
description: Upgrade an existing installation to a newer chart version.
---

This guide covers upgrading an installed chart, and the one-time steps some installs need.

Most upgrades are a plain `helm upgrade` after `helm repo update`. Read the chart's `CHANGELOG.md` for the versions you are skipping. The StatefulSets replace one pod at a time, the Backup (pod 1) before the Master (pod 0). A Backup counts as Ready once it is running and, with `activeRouting`, in sync with its Master (see [Module and version changes on a redundant pair](#module-and-version-changes-on-a-redundant-pair)).

## Before you upgrade

### Take a gateway backup

Before each upgrade, take a gateway backup (`.gwbk`) of every gateway with a data volume, and copy it out of the cluster. If a data volume doesn't survive the upgrade, the backup is the only way back:

```bash
kubectl exec -n <namespace> ignition-failover-0 -c gateway -- \
  /usr/local/bin/ignition/gwcmd.sh -b /usr/local/bin/ignition/temp/pre-upgrade.gwbk
kubectl cp -n <namespace> -c gateway ignition-failover-0:/usr/local/bin/ignition/temp/pre-upgrade.gwbk ./pre-upgrade.gwbk
```

Back up the Master (pod 0) of a pair; in scaleout, each backend gateway (`<name>-backend-0`, and `-1` for a pair). The frontends keep nothing on a volume. To restore a backup, see [Restore on first start](../capabilities/#restore-on-first-start).

### Pin the Ignition version

With `image.tag` empty, the gateways run the chart's `appVersion`, so a chart upgrade that raises it also upgrades Ignition. Pin the version you run, and change it on purpose, in an upgrade of its own:

```yaml
image:
  tag: "8.3.10"
```

Read Inductive Automation's release notes for every Ignition version you skip, and upgrade one environment at a time, test before production.

### Ignition 8.1 to 8.3 is one-way

Upgrading to 8.3 converts a gateway's data volume to 8.3's configuration format, and the 8.1 image won't start on it again. An 8.3 backup can't be restored on 8.1. Before moving to 8.3:

1. Take an 8.1 backup (above) and keep it.
2. Check that every module you use, third-party ones included, has an 8.3 version.

To go back, restore the 8.1 backup on an empty data volume with the 8.1 image.

### Module and version changes on a redundant pair

An upgrade that changes the pair's modules (`GATEWAY_MODULES_ENABLED`, or a chart's new default list) or its Ignition version replaces the Backup first, so for a while the Backup and Master differ. Ignition then reports the Backup as `RedundantState=Incompatible` (the Master as `Modules_Incompatible`), and logs `Master and backup are incompatible due to differences between installed modules` and `Could not disable module ... to match master`. Only replacing the Master fixes it.

With `activeRouting`, readiness counts an `Incompatible` Backup as Ready, so the rollout goes on to the Master; the gateway logs `[health-check] Backup is Incompatible with the Master ...`. While the Master restarts, the Backup takes over and the `-active` Service routes to it. The Backup then goes `OutOfDate` (not Ready, for about a minute) and `Good`, logging `[health-check] Backup is in sync with the Master again`. On a test cluster, adding or removing a module took about five minutes from `helm upgrade` to both gateways `Good`.

A Backup still `Incompatible` 30 minutes after it first reported it is not Ready until it is `Good`: the pair is broken, for example by a module installed on one gateway only. Check both gateways' modules and Ignition versions. For a Master that takes longer to start, raise the limit in seconds:

```yaml
ignition:                  # scaleout: backend
  config:
    IGNITION_READY_INCOMPATIBLE_SECONDS: "3600"
```

Kubernetes doesn't replace a StatefulSet pod that isn't Ready during a rolling update. If an upgrade with an earlier chart version is stuck on an `Incompatible` Backup, upgrading to this chart doesn't free it: after `helm upgrade`, delete the Backup's pod (`kubectl delete pod -n <namespace> ignition-failover-1`, or `<name>-backend-1`). The StatefulSet recreates it with this chart's readiness check, then replaces the Master.

## Breaking changes: EULA, passwords and the values schema

The charts' current major versions change what both charts need to render. Make each change in your values before `helm upgrade`; an upgrade without them fails to render and changes nothing in the cluster.

1. **Accept the EULA**: set `acceptEula: true` (see [If you relied on the default EULA acceptance](#if-you-relied-on-the-default-eula-acceptance)).
2. **Set the passwords**: set `GATEWAY_ADMIN_PASSWORD`, `IGNITION_GAN_KEYSTORE_PASSWORD` and `IGNITION_WEB_KEYSTORE_PASSWORD`, or name a Secret that holds them in `existingSecret` (see [If you relied on the default passwords](#if-you-relied-on-the-default-passwords)).
3. **Fix unknown keys**: values are validated against a schema, so a misspelt or unknown key the chart used to ignore now fails with `additional properties '<key>' not allowed`. Remove or correct it.

Check that your values render:

```bash
helm template <release> ignition-charts/<chart> -n <namespace> -f my-values.yaml > /dev/null
```

These changes need no step:

* **The gateways restart once**: the new checksum annotations (config, secrets, logging, scripts) and startup probe change the pod templates, so the first upgrade replaces every pod, the Backup before the Master. Upgrade in a maintenance window, or use `updateStrategy.type: OnDelete`.
* **Startup probe on by default**: a gateway has about 10 minutes to report `RUNNING` before the kubelet restarts it. For a slower start, raise `startupProbe.failureThreshold`.
* **Service ports**: the container ports stay on 8088, 8043 and 8060 whatever `service.ports` says. If you changed `service.ports`, NetworkPolicy rules (`networkPolicy.extraIngress`) must now name the gateway's own ports.
* **Scaleout frontend**: `frontend.logging` now configures the frontends (they used the backend's); the frontend Service uses `sessionAffinity: ClientIP` with more than one gateway unless you set `frontend.service.sessionAffinity`; the frontend PodDisruptionBudget needs a minimum of two gateways.

## Install-specific steps

Check these before you upgrade, and take each step that applies to your install.

### If you relied on the default EULA acceptance

The charts no longer accept Ignition's EULA for you: `ACCEPT_IGNITION_EULA: "Y"` is gone from the `config` defaults. Read Inductive Automation's [Ignition End User License Agreement](https://inductiveautomation.com/ignition/license), then set the top-level `acceptEula` (or `--set acceptEula=true`):

```yaml
acceptEula: true
```

The chart then sets `ACCEPT_IGNITION_EULA=Y` itself. Remove `ACCEPT_IGNITION_EULA` from your `config` values, as a value there still wins over `acceptEula`. A gateway that has already commissioned is unaffected either way.

### If you relied on the default passwords

The charts no longer default the passwords (`GATEWAY_ADMIN_PASSWORD` was `admin`, `IGNITION_GAN_KEYSTORE_PASSWORD` `metro`, `IGNITION_WEB_KEYSTORE_PASSWORD` `ignition`). An upgrade whose values don't set all three, or an `existingSecret` that holds them, fails to render and changes nothing:

```text
Error: ... the chart has no default passwords: set ignition.existingSecret to a Secret holding GATEWAY_ADMIN_PASSWORD, ...
```

To upgrade without changing the gateways, set the old values explicitly:

```yaml
ignition:                  # scaleout: frontend and backend
  secrets:
    GATEWAY_ADMIN_PASSWORD: admin
    IGNITION_GAN_KEYSTORE_PASSWORD: metro
    IGNITION_WEB_KEYSTORE_PASSWORD: ignition
```

Then change them to real passwords:

* `GATEWAY_ADMIN_PASSWORD` is applied only when the gateway commissions, so on an existing data volume also change it in the Gateway web UI.
* A new `IGNITION_GAN_KEYSTORE_PASSWORD` takes effect once cert-manager reissues the Gateway Network keystore (`cmctl renew <name>-gan`, or `<name>-frontend-gan` and `<name>-backend-gan`) and the gateway next starts.

To keep the passwords out of Helm's values, move them to a Secret of your own, set `existingSecret` (`ignition.existingSecret`, or `frontend.existingSecret` and `backend.existingSecret`) and remove them from `secrets`; see [Example: existingSecret](../capabilities/#example-existingsecret). The upgrade deletes the chart's own `<name>-secrets`, so first create yours with every key the gateways need, including `GATEWAY_ADMIN_USERNAME` if it isn't `admin`.

### If your StatefulSets name another Service

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

### If your data volumes are owned by root

The gateways run as user 2003. On storage that does not apply `fsGroup` (for example local-path), a data volume a gateway running as root wrote is owned by root, and the gateway cannot update it: its `preconfigure` init container fails with `Permission denied`. If your install ran the gateway as root, add this for the upgrade and remove it again once the pods are running:

```yaml
ignition:
  fixDataOwnership: true   # scaleout: frontend.fixDataOwnership and backend.fixDataOwnership
```

It adds an init container that chowns the volume as root (with only the `CHOWN`, `DAC_OVERRIDE` and `FOWNER` capabilities), so the namespace must allow the baseline Pod Security level while it is on.

### If traffic reaches the gateways from outside the namespace

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

### If other gateways join yours with your own CA

Each gateway trusts only its release's own Gateway Network CA, not the root of the issuer that signed it. With the default self-signed issuer the two are the same certificate. With your own CA issuer (`certManager.issuer.name`), a gateway outside the release whose certificate that issuer signs, such as another release or an external gateway, is refused on the Gateway Network. Give each such peer trust explicitly in the gateway's Gateway Network settings. An issuer that publishes no `ca.crt` (for example ACME) works too.

### If you use SealedSecrets

Each Gateway Network keystore takes its password from the release's own secrets (`<name>-secrets`, or `<name>-frontend-secrets` and `<name>-backend-secrets`, or the `existingSecret` you name), and the chart refuses a value in `secrets` that isn't sealed, the default user name included. If your release has a separate `<name>-gan-metro-keystore` Secret, the upgrade deletes it, and the keystore keeps the password from that Secret until cert-manager next issues the certificate. Once the upgrade has rendered, renew it (`cmctl renew <name>-gan`, or `<name>-frontend-gan` and `<name>-backend-gan`).

### If you autoscale the scaleout frontend

`frontend.hpa.enabled` needs `componentSelectors: true`, as without it the autoscaler also counts the backend's pods, and the chart fails to render. If your StatefulSets use the shared selector (`componentSelectors: false`), setting it changes both StatefulSets' selectors, which Kubernetes doesn't allow on an existing object. Delete only the StatefulSet objects first; the upgraded StatefulSets adopt the running pods:

```bash
kubectl delete statefulset <name>-frontend <name>-backend -n <namespace> --cascade=orphan
helm upgrade <release> ignition-charts/ignition-scaleout -n <namespace> ... --set componentSelectors=true
```

The recreated frontend StatefulSet starts at one gateway until the autoscaler raises it to `minReplicas`, so upgrade in a quiet period.
