# Ignition Common Library Chart

This is a library chart used by the `ignition-failover` and `ignition-scaleout` charts. It provides reusable templates and helper functions to ensure consistency across different deployment models.

## Available Templates

### Resource Generators (`_resources.tpl`)

* **`ignition-common.serviceAccount`**: Generates a standard ServiceAccount.
* **`ignition-common.configMap`**: Generates a ConfigMap for environment variable configuration.
* **`ignition-common.secret`**: Generates an Opaque Secret or Bitnami SealedSecret.
* **`ignition-common.ganCA`**: Generates a Cert-Manager Certificate and Issuer for the Gateway Network.
* **`ignition-common.ganCertificate`**: Generates a Cert-Manager Certificate for a specific node/component.
* **`ignition-common.pdb`**: Generates a PodDisruptionBudget.
* **`ignition-common.networkPolicy`**: Generates a NetworkPolicy to secure the Gateway Network.
* **`ignition-common.serviceMonitor`**: Generates a Prometheus Operator ServiceMonitor.
* **`ignition-common.hpa`**: Generates a HorizontalPodAutoscaler.

### Helper Scripts (`_scripts.tpl`)

* **`seed-data-volume.sh`**: Initializes the persistent data volume.
* **`seed-redundancy.sh`**: Configures the initial `redundancy.xml` based on pod ordinal.
* **`prepare-gan-certificates.sh`**: Injects GAN certificates into the Ignition data directory and GWBK files.
* **`health-check.sh`**: A robust probe script that verifies the Web Server and Gateway Network status.

### Helper Functions (`_helpers.tpl`)

* **`ignition.name`**: Returns the sanitized application name.
* **`ignition.fullname`**: Returns the sanitized full release name.
* **`ignition-common.podFQDN`**: Calculates the internal FQDN for a specific pod ordinal.

## Usage

To use these templates in an application chart, include this chart as a dependency and use the `include` function:

```yaml
{{ include "ignition-common.service" (dict "values" .Values.ignition "context" .) }}
```
