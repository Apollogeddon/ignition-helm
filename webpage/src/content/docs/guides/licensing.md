---
title: Licensing
order: 6
description: How to license Ignition gateways running in Kubernetes.
---

This page covers which licensing method fits gateways that Kubernetes reschedules, and how to license the charts' gateways. The charts pass the license key and activation token to the Ignition image as environment variables, from `secrets` or the Secret named by `existingSecret`, and the image activates them.

## Trial mode

Without a license, a gateway runs in trial mode, with every module working. On Ignition 8.3 the trial lasts two hours: then the modules stop until someone resets the trial from the Gateway web page, for another two hours. Restarting the gateway doesn't reset it. Trial mode suits trying the charts or a test environment; a production gateway needs a license. Check Inductive Automation's documentation for your version's trial rules.

## Leased licensing

Traditional Ignition licenses (6-character keys) are tied to the gateway's machine identity. In a container that depends on the image and the data volume, and can change when the pod is recreated or the image upgraded. That makes them a poor fit for rescheduled pods, and for the scaleout frontends, whose data volume is an emptyDir.

Use leased licensing with Kubernetes. A leased license (an 8-character key, `XXXX-XXXX`) has no fixed machine identity: each gateway checks out a lease session from Inductive Automation's licensing server with an activation token, and again after a restart.

For Kubernetes this means:

* **Resilience**: a rescheduled or recreated pod checks out a new lease.
* **Flexibility**: you can add frontend gateways without tracking machine IDs. Each running gateway holds one lease session, so the license needs as many sessions as the most gateways you run at once, rolling updates included.
* **No manual reactivation**: a restarted pod does not need its license activated again.
* **Network access**: each gateway must reach `licensing.inductiveautomation.com` over HTTPS (443). The charts' NetworkPolicy limits only incoming traffic; a cluster that limits egress must allow it.

## Passing the license key

The Ignition image reads two environment variables for leased activation:

| Variable | Value |
| --- | --- |
| `IGNITION_LICENSE_KEY` | The leased license key, `XXXX-XXXX`. Since 8.1.19, several keys may be given comma-separated. |
| `IGNITION_ACTIVATION_TOKEN` | The activation token that goes with the key (needs 8.1.8 or later). |

Both are sensitive: put them with the gateway passwords, never in `config` (a ConfigMap). With the chart's own Secret:

```yaml
ignition:                  # scaleout: frontend and backend
  secrets:
    GATEWAY_ADMIN_PASSWORD: "..."
    IGNITION_GAN_KEYSTORE_PASSWORD: "..."
    IGNITION_WEB_KEYSTORE_PASSWORD: "..."
    IGNITION_LICENSE_KEY: "ABCD-1234"
    IGNITION_ACTIVATION_TOKEN: "<activation token>"
```

With `sealedSecrets`, seal them like every other value. With `existingSecret`, add them to that Secret:

```bash
kubectl create secret generic my-ignition-secrets -n <namespace> \
  --from-literal=GATEWAY_ADMIN_PASSWORD=<admin password> \
  --from-literal=IGNITION_GAN_KEYSTORE_PASSWORD=<gan keystore password> \
  --from-literal=IGNITION_WEB_KEYSTORE_PASSWORD=<web keystore password> \
  --from-literal=IGNITION_LICENSE_KEY=ABCD-1234 \
  --from-literal=IGNITION_ACTIVATION_TOKEN=<activation token>
```

Changing the key in `secrets` restarts the gateways. After changing a Secret named by `existingSecret`, run `kubectl rollout restart statefulset/<name>`. Since 8.1.19 the image applies a changed key or token to a commissioned gateway; earlier versions read them only on a gateway's first start.

Inductive Automation recommends returning a stopping gateway's lease session, so a replacement pod can check one out at once instead of waiting for the old session to expire. If you scale gateways up and down often, add the gateway setting that does this (see Inductive Automation's leased-activation documentation) to `args`, after `--`.

## Frontend licensing (scaleout)

In the scaleout architecture, frontend gateways have no persistent volume and can be added or removed at any time. Leased licensing lets you scale them, including with a HorizontalPodAutoscaler, while each gateway checks out its own lease session. Set each layer's key in `frontend.secrets` and `backend.secrets`, or its `existingSecret`. Both layers can share a leased key with enough sessions for both.
