# Examples

Example values files for the `ignition-failover` and `ignition-scaleout` charts. Each one shows a single setup; combine them, or copy the parts you need into your own values file. Replace the example passwords before you use them.

## Failover (`failover/`)

| File | Shows |
| ---- | ----- |
| [`01-standalone.yaml`](failover/01-standalone.yaml) | A single gateway (no redundancy) behind a LoadBalancer Service. |
| [`02-redundancy.yaml`](failover/02-redundancy.yaml) | A Master/Backup redundant pair. |
| [`03-custom-web-ssl.yaml`](failover/03-custom-web-ssl.yaml) | Your own web server TLS keystore. |
| [`04-persistence.yaml`](failover/04-persistence.yaml) | A specific storage class and volume size. |
| [`05-restore-backup.yaml`](failover/05-restore-backup.yaml) | Fetching a gateway backup (`.gwbk`) from a URL before the gateway starts. |
| [`06-ingress-tls.yaml`](failover/06-ingress-tls.yaml) | An Ingress with a TLS certificate from cert-manager. |

These two also use the failover chart:

| File | Shows |
| ---- | ----- |
| [`database-integration.yaml`](database-integration.yaml) | Passing database connection details to the gateway as environment variables. |
| [`monitoring-stack.yaml`](monitoring-stack.yaml) | A Prometheus ServiceMonitor, larger resources and a matching JVM heap. |

## Scaleout (`scaleout/`)

| File | Shows |
| ---- | ----- |
| [`01-minimal.yaml`](scaleout/01-minimal.yaml) | One frontend and one backend gateway. |
| [`02-high-availability.yaml`](scaleout/02-high-availability.yaml) | A redundant backend pair and three frontend gateways. |
| [`03-resource-limits.yaml`](scaleout/03-resource-limits.yaml) | CPU and memory requests and limits, with a matching JVM heap. |

## Usage

From the repository root, pass a file to `helm install` or `helm upgrade` with `-f`:

```bash
# failover, redundant pair
helm install my-ignition ignition-charts/ignition-failover -f examples/failover/02-redundancy.yaml

# scaleout, redundant backend
helm install my-scaleout ignition-charts/ignition-scaleout -f examples/scaleout/02-high-availability.yaml
```
