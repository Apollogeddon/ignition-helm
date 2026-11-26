---
title: Upgrading
order: 5
description: Upgrade an existing installation to a newer chart version.
---

This guide covers upgrading an installed chart, and the one-time steps some installs need.

Most upgrades are a plain `helm upgrade` after `helm repo update`. Read the chart's `CHANGELOG.md` for the versions you are skipping. The StatefulSets replace one pod at a time, the Backup (pod 1) before the Master (pod 0), and a Backup only counts as Ready once it is running and, with `activeRouting`, in sync with its Master (see [Module and version changes on a redundant pair](#module-and-version-changes-on-a-redundant-pair)).

## Before you upgrade

### Take a gateway backup

Take a gateway backup (`.gwbk`) of every gateway with a data volume before each upgrade, and copy it out of the cluster. A chart upgrade can change the Ignition version, and if a gateway's data volume doesn't survive the upgrade, the backup is the only way back:

```bash
kubectl exec -n <namespace> ignition-failover-0 -c gateway -- \
  /usr/local/bin/ignition/gwcmd.sh -b /usr/local/bin/ignition/temp/pre-upgrade.gwbk
kubectl cp -n <namespace> -c gateway ignition-failover-0:/usr/local/bin/ignition/temp/pre-upgrade.gwbk ./pre-upgrade.gwbk
```

For a redundant pair, back up the Master (pod 0); in scaleout, back up each backend gateway (`<name>-backend-0`, and `-1` for a pair). The frontends keep nothing on a volume. To restore one, see [Restore on first start](../capabilities/#restore-on-first-start).

### Pin the Ignition version

With `image.tag` empty, the gateways run the chart's `appVersion`, so a chart upgrade that raises `appVersion` also upgrades Ignition, without your asking for it. Pin the version you run, and change it on purpose, in its own upgrade:

```yaml
image:
  tag: "8.3.10"
```

Read Inductive Automation's release notes for every Ignition version you skip, and upgrade one environment (test, then production) at a time.

### Ignition 8.1 to 8.3 is one-way

Upgrading a gateway from Ignition 8.1 to 8.3 converts its data volume to 8.3's configuration format, and an 8.3 gateway backup can't be restored on 8.1. There is no rolling back by setting `image.tag` to 8.1 again: the 8.1 gateway won't start on the converted volume. Before moving to 8.3, take an 8.1 backup (above), keep it, and check that every module and third-party module you use has an 8.3 version. To go back, restore the 8.1 backup on an empty data volume with the 8.1 image.

### Module and version changes on a redundant pair

An upgrade that changes the pair's modules (`GATEWAY_MODULES_ENABLED`, or a chart upgrade that changes its default list) or its Ignition version replaces the Backup first, so for a while the new Backup runs different modules from the old Master. Ignition reports the Backup as `RedundantState=Incompatible` (and the Master as `Modules_Incompatible`), and logs `Master and backup are incompatible due to differences between installed modules` and `Could not disable module ... to match master`. Only replacing the Master fixes that.

With `activeRouting`, readiness requires a Backup to be in sync, except in this one state: an `Incompatible` Backup counts as Ready, so the rolling update goes on to the Master, and the gateway logs `[health-check] Backup is Incompatible with the Master ...`. While the Master restarts, the Backup takes over and the `-active` Service routes to it. Once the Master is back, the Backup goes `OutOfDate` while it syncs (not Ready, for about a minute) and then `Good`, logging `[health-check] Backup is in sync with the Master again`. On a test cluster, adding or removing a module took about five minutes from `helm upgrade` to both gateways `Good`.

A pair that is still `Incompatible` 30 minutes after the Backup first reported it is broken rather than mid-upgrade, for example a module installed on one gateway only, and the Backup is not Ready again until it is `Good`: check both gateways' modules and Ignition versions. To allow longer, for a Master that takes a long time to start, set the limit in seconds:

```yaml
ignition:                  # scaleout: backend
  config:
    IGNITION_READY_INCOMPATIBLE_SECONDS: "3600"
```

Kubernetes doesn't replace a StatefulSet pod that isn't Ready during a rolling update. If an upgrade with an earlier chart version is already stuck with an `Incompatible` Backup that never goes Ready, upgrading to this chart doesn't move it on by itself: after `helm upgrade`, delete the Backup's pod (`kubectl delete pod -n <namespace> ignition-failover-1`, or `<name>-backend-1`), and the StatefulSet recreates it with this chart's readiness check and then replaces the Master.

## Breaking changes: EULA, passwords and the values schema

The charts' current major versions change what both charts need to render. Make each change below in your values before you run `helm upgrade`; an upgrade that doesn't fails to render, and nothing changes in the cluster.

1. **Accept the EULA**: set `acceptEula: true` (see [If you relied on the default EULA acceptance](#if-you-relied-on-the-default-eula-acceptance)).
2. **Set the passwords**: set `GATEWAY_ADMIN_PASSWORD`, `IGNITION_GAN_KEYSTORE_PASSWORD` and `IGNITION_WEB_KEYSTORE_PASSWORD`, or name a Secret that holds them with `existingSecret` (see [If you relied on the default passwords](#if-you-relied-on-the-default-passwords)).
3. **Fix unknown keys**: the charts now validate values against a schema, so a misspelt or unknown key, which the chart used to ignore, now fails the render with `additional properties '<key>' not allowed`. Remove the key, or correct it to the value you meant.

`helm template` with your values file shows whether it renders:

```bash
helm template <release> ignition-charts/<chart> -n <namespace> -f my-values.yaml > /dev/null
```

Other changes take effect on the upgrade without a step:

* **The gateways restart once**: the pod templates gain checksum annotations (config, secrets, logging, scripts) and a startup probe, so the first upgrade replaces every pod, the Backup before the Master. Upgrade in a maintenance window, or use `updateStrategy.type: OnDelete`.
* **Startup probe on by default**: a gateway has about 10 minutes to report `RUNNING` before the kubelet restarts it. If yours takes longer to start, raise `startupProbe.failureThreshold`.
* **Service ports**: the container ports stay on 8088, 8043 and 8060 whatever `service.ports` says, and the Service maps its ports to them. If you changed `service.ports`, NetworkPolicy rules (`networkPolicy.extraIngress`) must now name the gateway's own ports.
* **Scaleout frontend**: `frontend.logging` now configures the frontends (they used the backend's before); the frontend Service uses `sessionAffinity: ClientIP` with more than one gateway unless you set `frontend.service.sessionAffinity`; and the frontend PodDisruptionBudget only exists with a minimum of two gateways.

## Install-specific steps

Check these before you upgrade, and take each step that applies to your install.

### If you relied on the default EULA acceptance

The charts no longer accept Ignition's EULA for you: `ACCEPT_IGNITION_EULA: "Y"` is gone from the `config` defaults, and the charts refuse to render until you read Inductive Automation's [Ignition End User License Agreement](https://inductiveautomation.com/ignition/license) and set the top-level `acceptEula`:

```yaml
acceptEula: true
```

or `--set acceptEula=true`. The chart then sets `ACCEPT_IGNITION_EULA=Y` itself, so remove `ACCEPT_IGNITION_EULA` from your `config` values if you set it there: a value in `config` still wins over `acceptEula`. An existing gateway that already commissioned is not affected either way.

### If you relied on the default passwords

The charts no longer have default passwords (they were `admin` for `GATEWAY_ADMIN_PASSWORD`, `metro` for `IGNITION_GAN_KEYSTORE_PASSWORD` and `ignition` for `IGNITION_WEB_KEYSTORE_PASSWORD`). An upgrade whose values don't set all three, or name a Secret that holds them with `existingSecret`, fails to render, and nothing changes in the cluster:

```text
Error: ... the chart has no default passwords: set ignition.existingSecret to a Secret holding GATEWAY_ADMIN_PASSWORD, ...
```

To upgrade without changing anything on the gateways, set the old values explicitly, then change them deliberately later:

```yaml
ignition:                  # scaleout: frontend and backend
  secrets:
    GATEWAY_ADMIN_PASSWORD: admin
    IGNITION_GAN_KEYSTORE_PASSWORD: metro
    IGNITION_WEB_KEYSTORE_PASSWORD: ignition
```

Then choose real passwords. The image applies `GATEWAY_ADMIN_PASSWORD` when the gateway commissions, so on an existing data volume change the admin password in the Gateway web UI as well. A new `IGNITION_GAN_KEYSTORE_PASSWORD` only takes effect once cert-manager reissues the Gateway Network keystore with it (`cmctl renew <name>-gan`, or `<name>-frontend-gan` and `<name>-backend-gan`), and the next gateway start installs it.

To keep the passwords out of Helm's values, move them to a Secret of your own and set `existingSecret` (`ignition.existingSecret`, or `frontend.existingSecret` and `backend.existingSecret`), removing the passwords from `secrets`; see [Example: existingSecret](../capabilities/#example-existingsecret). The chart then deletes its own `<name>-secrets` Secret on the upgrade, so create yours with every key the gateways need first, including `GATEWAY_ADMIN_USERNAME` if it isn't `admin`.

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
