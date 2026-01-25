# Ignition Helm Chart Examples

This directory contains example `values.yaml` files for deploying the `ignition-failover` and `ignition-scaleout` Helm charts.

## Failover Examples (`examples/failover/`)

* **01-standalone.yaml**: A basic single-node deployment (no redundancy).
* **02-redundancy.yaml**: A standard Master/Backup redundant deployment.
* **03-custom-web-ssl.yaml**: Configuration for providing your own Web Server TLS certificate (keystore).
* **04-persistence.yaml**: Configuration with specific storage class and size requirements.

## Scaleout Examples (`examples/scaleout/`)

* **01-minimal.yaml**: A basic deployment with 1 Frontend node and 1 Backend node.
* **02-high-availability.yaml**: A robust deployment with a redundant Backend pair and multiple Frontend nodes.
* **03-resource-limits.yaml**: Example of defining CPU/Memory requests and limits for production sizing.

## Usage

To use these examples, pass them to `helm install` or `helm upgrade` using the `-f` flag:

```bash
# Deploy Failover with Redundancy
helm install my-ignition ignition-charts/ignition-failover -f examples/failover/02-redundancy.yaml

# Deploy Scaleout with HA
helm install my-scaleout ignition-charts/ignition-scaleout -f examples/scaleout/02-high-availability.yaml
```
