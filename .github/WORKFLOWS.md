# GitHub Workflows Documentation

This repository uses GitHub Actions to automate testing, quality assurance, documentation deployment, and the release process for the Ignition Helm charts.

## 🏗️ Orchestration: The Index Workflow

The [`.index.yaml`](./workflows/.index.yaml) workflow is the primary entry point for changes to the `main` branch. It orchestrates the execution of other workflows in a specific order:

1. **Updates**: Synchronizes `Chart.lock` files by running `helm dependency update`.
2. **Testing & Quality**: Runs the testing and quality suites in parallel.
3. **Release**: Triggered only after testing and quality checks pass.
4. **Webpage**: Updates the documentation site after a successful release.

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

- **Release Please**: Uses `googleapis/release-please-action` to parse conventional commits and automatically manage `CHANGELOG.md` updates and version bumps.
- **Chart Releaser**: Uses `helm/chart-releaser-action` to package charts, create GitHub Releases, and update the Helm repository index on the `main` branch.

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
