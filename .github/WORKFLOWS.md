# GitHub workflows

This page describes the GitHub Actions workflows that test, scan, release and document the Ignition Helm charts. It is for maintainers and contributors.

## Orchestration: the index workflow

The [`.index.yaml`](./workflows/.index.yaml) workflow is the primary entry point. It runs on pushes to `main` that change the charts and on every pull request, and orchestrates the other workflows in this order:

1. **Changes**: On a pull request, works out whether the charts, or the scripts and workflows that test and release them, changed, and whether any shell script changed.
2. **shellcheck**: Lints every shell script, when a script changed.
3. **Updates**: Synchronizes `Chart.lock` files by running `helm dependency update`, and commits any change on `main`.
4. **Testing & Quality**: Runs the testing and quality suites in parallel, when the charts changed.
5. **Release**: On `main` only, after testing and quality checks pass.
6. **Webpage**: On a pull request, the site's checks and build; on `main`, updates the site after a successful release.
7. **Auto-merge**: Merges a Dependabot pull request through [forgejs](https://github.com/apollogeddon/forgejs)'s `merge.yml`, once every job above has passed or been skipped.

A new push to a pull request cancels its previous run.

## Quality

The [`quality.yaml`](./workflows/quality.yaml) workflow focuses on static analysis and security scanning:

- **kube-linter**: renders the Helm charts and checks the manifests against Kubernetes best practices.
- **Trivy**: scans the charts for known vulnerabilities and misconfigurations.
- **Checkov**: scans the charts for security and compliance misconfigurations.

## Testing

The [`testing.yaml`](./workflows/testing.yaml) workflow ensures the functional integrity of the charts:

- **Unit tests**: `helm-unittest` checks the templates against the tests in `charts/*/tests`.
- **Script tests**: runs `test/scripts/*_test.sh` against the shell scripts the charts ship.
- **Linting**: `chart-testing` (`ct lint`) checks the charts' structure, with each chart's default values and its `ci/deploy-values.yaml`.
- **Integration tests**:
  - Creates a kind cluster and installs cert-manager with a self-signed `cluster-issuer` (`.github/scripts/ci/install-cert-manager.sh`).
  - Runs `.github/scripts/tests/deploy-test.sh` for each changed chart (both, when the common chart changes). It installs the chart with its `ci/deploy-values.yaml` and checks the running gateways: RUNNING without restarts, the NetworkPolicy blocking another namespace, the scaleout frontend reaching its backend, and the chart options in effect. It then installs the `main` branch's chart and upgrades it to this one.

The [`e2e.yaml`](./workflows/e2e.yaml) workflow, run manually, runs the end-to-end scenarios in [`test/e2e`](../test/e2e/README.md) on a disposable kind cluster.

## Release

The [`release.yaml`](./workflows/release.yaml) workflow automates versioning and publishing:

- **Chart releases**: Packages every chart, and creates a tag and GitHub Release named `<chart>-v<version>` with the chart attached for each chart version that has no release yet. Before each release exists, cosign signs the chart keyless with the workflow's GitHub OIDC identity (the `version` job is the only one with `id-token: write`) and checks the signature, writing a Sigstore bundle, `<chart>-<version>.tgz.sigstore.json`. `gh` creates each release as a draft, attaches the chart and its bundle and then publishes it, as the repository's releases are immutable once published. The [README](../README.md#verifying-a-chart) has the `cosign verify-blob` command that checks a chart. chart-releaser then adds the new versions to the Helm repository index on the `main` branch. Each release's description is the newest section of the chart's `CHANGELOG.md`.
- **Release Please**: Parses conventional commits and opens the release pull requests that bump each chart's version and `CHANGELOG.md`. It creates no releases of its own (`skip-github-release`), so each chart version gets exactly one tag and one release, and the workflow marks a merged release pull request as released once its chart versions are released.

Every workflow installs Helm through [`.github/actions/setup-helm`](./actions/setup-helm/action.yml), which sets the Helm version in one place.

## Documentation site

The [`webpage.yaml`](./workflows/webpage.yaml) workflow manages the [Astro](https://astro.build/)-based documentation site. After its own Markdown job, it calls [forgejs](https://github.com/apollogeddon/forgejs)'s [`website.yml`](https://github.com/apollogeddon/forgejs/blob/main/.github/workflows/website.yml) with `working_directory: webpage`:

- **Markdown**: Lints every Markdown file in the repository with `markdownlint-cli2`.
- **Quality**: Gitleaks over the whole repository, OSV-Scanner on the site's dependencies, Biome and the type check.
- **Build**: A pre-build command copies the chart repository's `index.yaml` into the site, which is then built from the `webpage/` directory, on pull requests too, so a broken site fails the pull request. Pushes and release calls build the tip of `main` (`ref: main`), which has the `index.yaml` chart-releaser just pushed.
- **Deploy**: On `main`, publishes the build to **GitHub Pages**, which also serves the Helm repository, and commits OSV-Scanner's security patches to the site's dependencies.

## Configuration

- **`release.json`** and **`.release.json`**: release-please's configuration (the chart packages and how their changelogs are written) and manifest (each chart's current version).
- **`dependabot.yml`**: keeps the Helm chart dependencies, the npm packages (the root tooling and the `webpage/` site) and the GitHub Actions up to date.
- **`ct.yaml`** (repository root): configuration for `chart-testing`, used by the testing workflow.
