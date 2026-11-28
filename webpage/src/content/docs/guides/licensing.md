---
title: Licensing
order: 6
description: How to license Ignition gateways running in Kubernetes.
---

The charts pass a license key and activation token to the Ignition image as environment variables, from `secrets` or `existingSecret`, and the image activates them.

## Trial mode

Without a license, a gateway runs in trial mode with every module working. On 8.3 the trial lasts two hours, until someone resets it from the Gateway web page; a restart doesn't reset it. Production gateways need a license.

## Leased licensing

Use leased licensing. Traditional licenses (6-character keys) are tied to the machine identity, which in a container changes with the pod, image or data volume; scaleout frontends have only an emptyDir. A leased license (`XXXX-XXXX`) has no machine identity: each gateway checks out a lease session with an activation token, and again after a restart.

* **Resilience**: a rescheduled or recreated pod checks out a new lease, with no manual reactivation.
* **Sessions**: each running gateway holds one, so buy enough for the most gateways you run at once, rolling updates included.
* **Network access**: each gateway must reach `licensing.inductiveautomation.com` on 443. The charts' NetworkPolicy limits only incoming traffic, so allow it in any egress policy.

## Passing the license key

| Variable | Value |
| --- | --- |
| `IGNITION_LICENSE_KEY` | The leased key, `XXXX-XXXX`; comma-separated keys since 8.1.19 |
| `IGNITION_ACTIVATION_TOKEN` | Its activation token (8.1.8 or later) |

Put them with the gateway passwords, never in `config` (a ConfigMap):

```yaml
ignition:                  # scaleout: frontend and backend
  secrets:
    GATEWAY_ADMIN_PASSWORD: "..."
    IGNITION_GAN_KEYSTORE_PASSWORD: "..."
    IGNITION_WEB_KEYSTORE_PASSWORD: "..."
    IGNITION_LICENSE_KEY: "ABCD-1234"
    IGNITION_ACTIVATION_TOKEN: "<activation token>"
```

With `sealedSecrets`, seal them too. With `existingSecret`, add them to that Secret (`--from-literal=IGNITION_LICENSE_KEY=ABCD-1234 --from-literal=IGNITION_ACTIVATION_TOKEN=<activation token>`).

* A changed key in `secrets` restarts the gateways; to roll them when an `existingSecret` changes, put a hash of its data in `<prefix>.podAnnotations` (names under `checksum/` are the chart's own), or run `kubectl rollout restart statefulset/<name>`.
* Since 8.1.19 the image applies a changed key to a commissioned gateway; earlier versions read it only on the first start.
* If you scale gateways often, add the gateway setting that returns a stopping gateway's lease session (see Inductive Automation's leased-activation documentation) to `args`, after `--`, so a replacement pod needn't wait for it to expire.

## Frontend licensing (scaleout)

Frontend gateways have no persistent volume and come and go, including with a HorizontalPodAutoscaler; each checks out its own lease session. Set each layer's key in `frontend.secrets` and `backend.secrets`, or its `existingSecret`. Both layers can share a key with enough sessions.
