# GitHub Workflows Documentation

This repository uses GitHub Actions to automate testing, quality assurance, documentation deployment, and the release process for the Ignition Helm charts.

## 🏗️ Orchestration: The Index Workflow

The [`.index.yaml`](./workflows/.index.yaml) workflow is the primary entry point. It runs on pushes to `main` that change the charts and on every pull request, and orchestrates the other workflows in this order:

1. **Changes**: On a pull request, works out whether the charts, or the scripts and workflows that test and release them, changed, and whether any shell script changed.
2. **shellcheck**: Lints every shell script, when a script changed.
3. **Updates**: Synchronizes `Chart.lock` files by running `helm dependency update`, and commits any change on `main`.
4. **Testing & Quality**: Runs the testing and quality suites in parallel, when the charts changed.
5. **Release**: On `main` only, after testing and quality checks pass.
6. **Webpage**: On a pull request, the site's checks and build; on `main`, updates the site after a successful release.
7. **Auto-merge**: Merges a Dependabot pull request through [forgejs](https://github.com/apollogeddon/forgejs)'s `merge.yml`, once every job above has passed or been skipped.

A new push to a pull request cancels its previous run.

---

## 🔍 Quality Assurance

The [`quality.yaml`](./workflows/quality.yaml) workflow focuses on static analysis and security scanning:

- **Kube-Linter**: Renders the Helm charts and scans the resulting manifests for Kubernetes best practices.
- **Trivy**: Scans the charts for known vulnerabilities and configuration issues.
- **Checkov**: A static code analysis tool for Infrastructure-as-Code (IaC) to detect security and compliance misconfigurations.

## 🧪 Testing

The [`testing.yaml`](./workflows/testing.yaml) workflow ensures the functional integrity of the charts:

- **Unit Tests**: Uses `helm-unittest` to verify template logic against defined expectations in `charts/*/tests`.
- **Linting**: Uses `chart-testing` (`ct lint`) to ensure charts meet Helm's structural requirements.
- **Integration Tests**:
  - Spins up a local Kubernetes cluster using **Kind** and installs cert-manager.
  - Runs `.github/scripts/tests/deploy-test.sh` for each changed chart: a fresh install with the chart's `ci/deploy-values.yaml`, checked on the running gateways (RUNNING without restarts, NetworkPolicy enforcement, frontend to backend connectivity, chart options in effect), then an upgrade from the `main` branch's chart.

## 🚀 Release Process

The [`release.yaml`](./workflows/release.yaml) workflow automates versioning and publishing:

- **Chart releases**: Packages every chart, and creates a tag and GitHub Release named `<chart>-<version>` with the chart attached for each chart version that has no release yet. `gh` creates each release as a draft, attaches the chart and then publishes it, as the repository's releases are immutable once published. chart-releaser then adds the new versions to the Helm repository index on the `main` branch. Each release's description is the newest section of the chart's `CHANGELOG.md`.
- **Release Please**: Parses conventional commits and opens the release pull requests that bump each chart's version and `CHANGELOG.md`. It creates no releases of its own (`skip-github-release`), so each chart version gets exactly one tag and one release, and the workflow marks a merged release pull request as released once its chart versions are released.

Every workflow installs Helm through [`.github/actions/setup-helm`](./actions/setup-helm/action.yml), which sets the Helm version in one place.

## 📖 Documentation

The [`webpage.yaml`](./workflows/webpage.yaml) workflow manages the [Astro](https://astro.build/)-based documentation site:

- **Quality**: Calls [forgejs](https://github.com/apollogeddon/forgejs)'s `quality.yml`: Gitleaks over the whole repository, OSV-Scanner on the site's dependencies, Biome and the type check.
- **Markdown**: Lints every Markdown file in the repository with `markdownlint-cli2`.
- **Build**: Copies the chart repository's `index.yaml` into the site and builds the static site located in the `webpage/` directory, on pull requests too, so a broken site fails the pull request. Pushes and release calls build the tip of `main`, which has the `index.yaml` chart-releaser just pushed.
- **Deploy**: Outside pull requests, publishes the build artifacts to **GitHub Pages**, which also serves the Helm repository.

---

## 🛠️ Configuration & Maintenance

- **`release.json`**: Configures the behavior of `release-please`, defining which paths trigger releases and how changelogs are generated.
- **`dependabot.yml`**: Automatically keeps GitHub Actions and Helm chart dependencies (defined in `charts/*/Chart.yaml`) up to date.
- **`ct.yaml`**: Configuration for the `chart-testing` tool used in the testing workflow.
