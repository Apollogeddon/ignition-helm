---
title: Licencing & Machine IDs
description: Managing Ignition licencing in Kubernetes.
---

One of the challenges with running Ignition in containers is that the **Machine ID**—which the licence key is tied to—changes every time the container is recreated. To solve this, these Helm charts provide a mechanism to spoof a static Machine ID.

## The `spoofMachineId` Parameter

Both the `failover` and `scaleout` charts expose a `spoofMachineId` parameter. When set, this value is injected into the container as the Machine ID, ensuring your licence remains valid across pod restarts.

### Step 1: Generate a Machine ID

You can generate a valid Machine ID using a simple 8-character alphanumeric string (hexadecimal is common).

```bash
# Example: Using openssl
openssl rand -hex 4
# Output: 9a2b3c4d
```

### Step 2: Configure Helm

Apply this ID in your `values.yaml` or via the `--set` flag.

**In `values.yaml`:**

```yaml
ignition:
  spoofMachineId: "9a2b3c4d"
```

**Via CLI:**

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.spoofMachineId="9a2b3c4d"
```

### Step 3: Activate Ignition

1. Start your Ignition Gateway.
2. Navigate to the Gateway Web Page -> Config -> Licencing.
3. You will see your spoofed Machine ID (`9a2b3c4d`) listed.
4. Activate your licence against this ID on the Inductive Automation website.

## Multiple Pods (Scaleout)

For the **Scaleout** architecture, you typically only licence the **Backend** gateway, as Frontends are often unlicenced (using the 2-hour trial for Perspective sessions) or use a flexible licence model.

However, if you need licenced Frontends, you must ensure each replica gets a unique licence or use the **Leased Licencing** model (supported by Ignition 8.1+).

### Leased Licencing

For dynamic environments like Kubernetes, the **8-character Licence Key** (Leased Licencing) is the preferred method. It does not rely on Machine IDs but instead checks out a licence session from a licence server.

If using Leased Licencing, you **do not** need to set `spoofMachineId`.
