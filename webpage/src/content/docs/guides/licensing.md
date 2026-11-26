---
title: Licensing
order: 6
description: How to license Ignition gateways running in Kubernetes.
---

This page explains which licensing method fits gateways that Kubernetes reschedules, and how to give the charts' gateways a license. The charts don't activate licenses themselves: they pass the license key and activation token to the Ignition image as environment variables, from `secrets` or a Secret you name with `existingSecret`, and the image activates them.

## Trial mode

Without a license, a gateway runs in trial mode, with every module working. On Ignition 8.3 the trial runs for two hours at a time: when it expires, the gateway's modules stop working until someone resets the trial from the Gateway web page, which starts another two hours. Restarting the gateway does not license it. That is fine for trying the charts out or for a test environment, but a production gateway needs a license. Check Inductive Automation's documentation for the trial rules of the version you run.

## Leased licensing

Traditional Ignition licenses (6-character keys) are tied to the gateway's machine identity, which in a container depends on the image and the data volume, and can change when the pod is recreated or the image upgraded. That makes them a poor fit for pods that Kubernetes reschedules, and for the scaleout frontends, whose data volume is an emptyDir.

Leased licensing is the method to use with Kubernetes. A leased license (an 8-character key, `XXXX-XXXX`) doesn't depend on a fixed machine identity: each gateway checks out a lease session from Inductive Automation's licensing server with an activation token, and checks it out again after a restart.

For Kubernetes this means:

* **Resilience**: a rescheduled or recreated pod checks out a new lease.
* **Flexibility**: you can add frontend gateways without tracking machine IDs. Each running gateway holds one lease session, so the license needs as many sessions as the most gateways you run at once, including during a rolling update.
* **No manual reactivation**: a restarted pod does not need its license activated again.
* **Network access**: each gateway must reach the licensing server (`licensing.inductiveautomation.com` over HTTPS, port 443). The charts' NetworkPolicy only limits incoming traffic, but a cluster that limits egress must allow it.

## Passing the license key

The Ignition image reads two environment variables for leased activation:

| Variable | Value |
| --- | --- |
| `IGNITION_LICENSE_KEY` | The leased license key, `XXXX-XXXX`. Since 8.1.19, several keys may be given comma-separated. |
| `IGNITION_ACTIVATION_TOKEN` | The activation token that goes with the key (needs 8.1.8 or later). |

Both are sensitive, so put them where the gateway passwords go, never in `config` (a ConfigMap). With the chart's own Secret:

```yaml
ignition:                  # scaleout: frontend and backend
  secrets:
    GATEWAY_ADMIN_PASSWORD: "..."
    IGNITION_GAN_KEYSTORE_PASSWORD: "..."
    IGNITION_WEB_KEYSTORE_PASSWORD: "..."
    IGNITION_LICENSE_KEY: "ABCD-1234"
    IGNITION_ACTIVATION_TOKEN: "<activation token>"
```

With `sealedSecrets`, seal the license key and token like every other value. With `existingSecret`, add them to that Secret, as every key in it becomes an environment variable in the gateway:

```bash
kubectl create secret generic my-ignition-secrets -n <namespace> \
  --from-literal=GATEWAY_ADMIN_PASSWORD=<admin password> \
  --from-literal=IGNITION_GAN_KEYSTORE_PASSWORD=<gan keystore password> \
  --from-literal=IGNITION_WEB_KEYSTORE_PASSWORD=<web keystore password> \
  --from-literal=IGNITION_LICENSE_KEY=ABCD-1234 \
  --from-literal=IGNITION_ACTIVATION_TOKEN=<activation token>
```

The chart's pod checksums cover its own Secret, so changing the key in `secrets` restarts the gateways; after changing a Secret named by `existingSecret`, restart them yourself (`kubectl rollout restart statefulset/<name>`). Since 8.1.19 the image also applies a changed key or token to a gateway that is already commissioned; earlier versions only read them on a gateway's first start.

When a gateway stops, Inductive Automation recommends returning its lease session to the licensing server, so a replacement pod can check one out straight away instead of waiting for the old session to expire. See Inductive Automation's leased-activation documentation for the gateway setting that does this, and add it to `args` (after `--`) if you scale gateways up and down often.

## Frontend licensing (scaleout)

In the scaleout architecture, frontend gateways have no persistent volume and can be added or removed at any time. Leased licensing lets you scale them, including with a HorizontalPodAutoscaler, while each gateway checks out its own lease session. Give the frontend and backend their keys in `frontend.secrets` and `backend.secrets` (or each layer's `existingSecret`); they can be the same leased key if it has enough sessions for both layers.
