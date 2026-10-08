# GitHub Workflows Documentation

This repository uses GitHub Actions to automate testing, quality assurance, documentation deployment, and the release process for the Ignition Helm charts.

## 🏗️ Orchestration: The Index Workflow

The [`.index.yaml`](./workflows/.index.yaml) workflow is the primary entry point for changes to the charts. It runs on pushes to `main` and on pull requests that change the charts or the workflows they use, and orchestrates the other workflows in this order:

1. **Updates**: Synchronizes `Chart.lock` files by running `helm dependency update`, and commits any change on `main`.
2. **Testing & Quality**: Runs the testing and quality suites in parallel.
3. **Release**: On `main` only, after testing and quality checks pass.
4. **Webpage**: Updates the documentation site after a successful release.

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
  - Spins up a local Kubernetes cluster using **Kind**.
  - Performs a `ct install` to verify the charts can be deployed.
  - Executes specific deployment tests (e.g., checking `StatusPing` via `kubectl exec`) for both Failover and Scaleout architectures.

## 🚀 Release Process

The [`release.yaml`](./workflows/release.yaml) workflow automates versioning and publishing:

- **Chart Releaser**: Packages every chart and creates a tag and GitHub Release, named `<chart>-<version>` with the chart attached, for each chart version that has no release yet. It then adds the new versions to the Helm repository index on the `main` branch. Each release's description is the newest section of the chart's `CHANGELOG.md`.
- **Release Please**: Parses conventional commits and opens the release pull requests that bump each chart's version and `CHANGELOG.md`. It creates no releases of its own (`skip-github-release`), so each chart version gets exactly one tag and one release, and the workflow marks a merged release pull request as released once chart-releaser has released it.

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
