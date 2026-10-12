<br />
<div align="center">
  <a href="https://apollogeddon.github.io/ignition-helm">
    <img src="webpage/public/favicon.png" alt="Logo" width="100" height="100">
  </a>
  <h3 align="center">Ignition Helm Charts</h3>
  <p align="center">
    Helm charts for running Ignition on Kubernetes, as a redundant Master/Backup pair or as separate frontend and backend gateways.
    <br />
    <a href="https://apollogeddon.github.io/ignition-helm"><strong>Read the docs</strong></a>
    <br />
    <br />
    <a href="https://apollogeddon.github.io/ignition-helm/docs/guides/installation/">Getting started</a>
    &middot;
    <a href="https://apollogeddon.github.io/ignition-helm/docs/charts/failover/">Failover chart</a>
    &middot;
    <a href="https://apollogeddon.github.io/ignition-helm/docs/charts/scaleout/">Scaleout chart</a>
  </p>
</div>

## Overview

This repository holds Helm charts that deploy Ignition gateways on Kubernetes, either as a redundant Master/Backup pair or as a scaleout architecture with separate frontend and backend gateways. They are for teams that run Ignition on their own clusters and want redundancy, Gateway Network certificates and upgrades handled by the chart.

| Chart | Description |
| ----- | ----------- |
| [`ignition-failover`](charts/failover/README.md) | One gateway, or a Master/Backup redundant pair. |
| [`ignition-scaleout`](charts/scaleout/README.md) | A backend gateway (optionally a redundant pair) and a scalable set of frontend gateways. |
| [`ignition-common`](charts/common/README.md) | Library chart with the templates the other two share. You do not install it directly. |

## Features

- **Failover architecture**: Master/Backup redundancy, with the redundancy settings applied to each gateway's volume on every start.
- **Scaleout architecture**: separate frontend (Perspective) and backend (devices, tags, history) gateways, connected over the Gateway Network.
- **Automated setup**: an init container seeds the data volume, the redundancy configuration and the Gateway Network certificates before the gateway starts.
- **Security**: runs as a non-root user that meets the Kubernetes restricted Pod Security level, issues Gateway Network certificates through cert-manager, supports SealedSecrets, and isolates Gateway Network traffic with a NetworkPolicy.
- **Operations**: Prometheus `ServiceMonitor`, health probes based on `/StatusPing`, optional routing to the active gateway only, and certificate rotation.
- **Scaling**: HorizontalPodAutoscaler support for the scaleout frontend.

## Requirements

- Kubernetes 1.23 or later, with a storage class that can provision persistent volumes.
- Helm 3. The CI workflows use Helm v3.22.0.
- [cert-manager](https://cert-manager.io/docs/installation/) and a `ClusterIssuer` named `cluster-issuer` (configurable with `certManager.issuer.name` and `certManager.issuer.kind`). The charts create cert-manager `Certificate` and `Issuer` resources for the Gateway Network, so they do not install without it. See [Installation](https://apollogeddon.github.io/ignition-helm/docs/guides/installation/) for a self-signed issuer you can use to get started.

## Installation

The charts are published as GitHub releases, one per chart version, and indexed in a Helm repository served from the documentation site. Add the repository:

```bash
helm repo add ignition-charts https://apollogeddon.github.io/ignition-helm
helm repo update
```

### Verifying a chart

Each chart version's release carries a [Sigstore](https://www.sigstore.dev/) bundle beside the chart, `<chart>-<version>.tgz.sigstore.json`. The release workflow signs the chart keyless with [cosign](https://docs.sigstore.dev/cosign/) before the release is published, so the bundle ties the exact `.tgz` the Helm repository serves to this repository's release workflow on `main`, and the signature is recorded in the public Rekor transparency log. To check a chart before installing it, with [cosign](https://docs.sigstore.dev/cosign/system_config/installation/) v3 or later and the [GitHub CLI](https://cli.github.com/) (or download the bundle from the release page):

```bash
helm pull ignition-charts/ignition-scaleout --version <version>
gh release download ignition-scaleout-v<version> --repo Apollogeddon/ignition-helm --pattern '*.sigstore.json'
cosign verify-blob ignition-scaleout-<version>.tgz \
  --bundle ignition-scaleout-<version>.tgz.sigstore.json \
  --certificate-identity https://github.com/Apollogeddon/ignition-helm/.github/workflows/release.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

`Verified OK` means the chart was built and released by this repository's release workflow and hasn't changed since. Chart versions released before signing was added have no bundle.

## Quick start

Install a single failover gateway. Set your own admin password; the default is `admin`.

```bash
helm install my-ignition ignition-charts/ignition-failover \
  --set ignition.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```

Add `--set ignition.redundancy.enabled=true` for a Master/Backup pair.

Install the scaleout chart:

```bash
helm install my-scaleout ignition-charts/ignition-scaleout \
  --set backend.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword \
  --set frontend.secrets.GATEWAY_ADMIN_PASSWORD=mysecretpassword
```

The [`examples/`](examples/README.md) directory has values files for common setups.

## Documentation

- [Documentation site](https://apollogeddon.github.io/ignition-helm): installation, architecture, configuration and upgrade guides.
- Chart READMEs: [failover](charts/failover/README.md), [scaleout](charts/scaleout/README.md), [common](charts/common/README.md).
- [Test plan](docs/test-plan.md) and [end-to-end tests](test/e2e/README.md).
- [Workflows](.github/WORKFLOWS.md) and [security policy](.github/SECURITY.md).

## Contributing

Pull requests are welcome. Run `npm ci` once per clone to install the commit hook. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), which release-please uses to version the charts. The failover and scaleout charts each ship the ignition-common they were released with, so when common is released the release workflow opens a pull request raising both to require it; merging that pull request releases them with it. Installing needs a GitHub token with `read:packages` in your user `~/.npmrc`, for `@apollogeddon/forgejs`.

## License

Released under the [MIT License](LICENSE).

Ignition is a trademark of Inductive Automation.
