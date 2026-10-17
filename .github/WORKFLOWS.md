# GitHub workflows

This page describes the GitHub Actions workflows that test, scan, release and document the Ignition Helm charts. It is for maintainers and contributors.

## CI orchestration

The root workflow, [`.index.yml`](./workflows/.index.yml) (`index`), runs on every pull request, every push to `main`, a manual run, the `auto-merged` dispatch the merge pipeline sends, and weekly for the patch pipeline. Each of its jobs calls one pipeline, or is a stage of one, so the run page lists every job as `<pipeline> / <stage>`. The pipelines are this repository's own [`charts.yml`](./workflows/charts.yml) and [`version.yml`](./workflows/version.yml), and [forgejs](https://github.com/apollogeddon/forgejs)'s shared `website.yml`, `pages.yml`, `patch.yml` and `merge.yml`.

| Job | Pipeline | Runs |
| --- | --- | --- |
| `changes` | (this workflow) | Always: works out whether the charts, their examples, or the scripts and workflows that test and release them changed, and whether any shell script changed. A manual run or a merge's dispatch checks everything |
| `charts / lint`, `scan (trivy)`, `scan (checkov)`, `test`, `test (cluster)` | `charts.yml` | On a pull request or a push to `main` that changes the charts or a script ([Charts](#charts)) |
| `version / release` | `version.yml` | On `main`, once the chart checks pass or are skipped, except on the weekly schedule ([Releases](#releases)) |
| `website / lint`, `scan`, `build`, `check` | forgejs's `website.yml` | Every run but the weekly one, on `main` after the release ([Documentation site](#documentation-site)) |
| `website / lint (markdown)` | (this workflow) | Every run but the weekly one |
| `pages / deploy` | forgejs's `pages.yml` | On `main`, once the site's checks pass |
| `patch / update` | forgejs's `patch.yml` | Weekly, on a manual run, and after the `auto-merged` dispatch ([Patches](#patches)) |
| `merge / review`, `merge / squash` | forgejs's `merge.yml` | On Dependabot's pull requests, once every check above passed or was skipped ([Dependabot](#dependabot)) |

The [`.e2e.yml`](./workflows/.e2e.yml) workflow (`e2e`), run by hand, calls `charts.yml` for its staging stage alone, `charts / test (staging)` ([End-to-end scenarios](#end-to-end-scenarios)).

A new push to a pull request cancels its previous run. Every other run has a concurrency group of its own, so a run on `main`, running or queued, is never cancelled; `version / release` takes one release at a time, so two runs on `main` never race for the same tags or the chart index.

Every workflow installs Helm through [`.github/actions/setup-helm`](./actions/setup-helm/action.yml), which sets the Helm version in one place. Every checkout keeps no token (`persist-credentials: false`) except the release's, which pushes the chart locks, the tags and the chart index.

## Charts

[`charts.yml`](./workflows/charts.yml) checks the charts and the scripts. The `changes` job passes it which of the two changed: a change to a shell script alone runs only the lint stage's shellcheck.

`charts / lint`:

- **shellcheck**: lints every shell script in the repository, with a pinned shellcheck version.
- **chart-testing**: `ct lint` checks the changed charts' structure, with each chart's default values and its `ci/deploy-values.yaml`.
- **kube-linter**: renders the charts and checks the manifests against Kubernetes best practices.

`charts / scan (trivy)`: scans the charts for misconfigurations, failing on high or critical ones.

`charts / scan (checkov)`: scans the charts for security and compliance misconfigurations.

`charts / test`:

- **Unit tests**: `helm-unittest` checks the templates against the tests in `charts/*/tests`.
- **Script tests**: runs `test/scripts/*_test.sh` against the shell scripts the charts ship. `examples_test.sh` also renders every values file in `examples/` with its chart, and fails when an example exposes a gateway beyond its namespace (a LoadBalancer, an Ingress, a ServiceMonitor or a NodePort it asks for) without a NetworkPolicy rule that lets the traffic in. It checks the e2e values in `test/e2e/values` the same way, for the Ingress and NodePort paths the scenarios measure.

`charts / test (cluster)`, once the tests pass:

- Creates a kind cluster and installs cert-manager with a self-signed `cluster-issuer` (`.github/scripts/ci/install-cert-manager.sh`).
- Runs `.github/scripts/tests/deploy-test.sh` for each changed chart (both, when the common chart, the deploy test, the kind or cert-manager setup, `ct.yaml` or `charts.yml` changes). It installs the chart with its `ci/deploy-values.yaml` and checks the running gateways: RUNNING without restarts, the NetworkPolicy blocking another namespace, the scaleout frontend reaching its backend, and the chart options in effect. It then installs the `main` branch's chart and upgrades it to this one, with the chart's `ci/upgrade-values.yaml` where it has one (the scaleout chart's leaves out the autoscaler, whose `componentSelectors` can't be turned on by an upgrade).

## End-to-end scenarios

`charts / test (staging)` runs the end-to-end scenarios in [`test/e2e`](../test/e2e/README.md) on a disposable three-node kind cluster with cert-manager, Contour and Chaos Mesh, and uploads their results. Only the [`.e2e.yml`](./workflows/.e2e.yml) workflow runs it, by hand with a read-only token, as a full run takes about two hours; its form takes the scenarios to run.

## Releases

[`version.yml`](./workflows/version.yml) automates versioning and publishing, as `version / release`. It stays local rather than forgejs's `version.yml`, as release-please creates no releases here: the job releases each chart version itself and keeps the chart index.

- **Chart locks**: Synchronizes the `Chart.lock` files with `helm dependency update`, and commits any change to `main`.
- **Chart releases**: Packages every chart, and creates a tag and GitHub Release named `<chart>-v<version>` with the chart attached for each chart version that has no release yet. Before each release exists, cosign signs the chart keyless with the workflow's GitHub OIDC identity (only this job has `id-token: write`), as `.github/workflows/version.yml`, and checks the signature, writing a Sigstore bundle, `<chart>-<version>.tgz.sigstore.json`. `gh` creates each release as a draft, attaches the chart and its bundle and then publishes it, as the repository's releases are immutable once published. The [README](../README.md#verifying-a-chart) has the `cosign verify-blob` command that checks a chart. chart-releaser then adds the new versions to the Helm repository index on the `main` branch. Each release's description is the newest section of the chart's `CHANGELOG.md`.
- **Release Please**: Parses conventional commits and opens the release pull requests that bump each chart's version and `CHANGELOG.md`, and asks for their review. It creates no releases of its own (`skip-github-release`), so each chart version gets exactly one tag and one release, and the job marks a merged release pull request as released once its chart versions are released.
- **ignition-common**: Once common has a new version, opens the pull request that raises the charts to require it.

It is passed no secrets: it needs only the workflow's own token.

## Documentation site

The `website` job calls [forgejs](https://github.com/apollogeddon/forgejs)'s `website.yml` on the [Astro](https://astro.build/)-based site in `webpage/`:

- **`website / lint (markdown)`**: Lints every Markdown file in the repository with `markdownlint-cli2`.
- **`website / lint`** and **`website / scan`**: Gitleaks over the whole repository, OSV-Scanner on the site's dependencies, Biome and the type check.
- **`website / build`**: A pre-build command copies the chart repository's `index.yaml` into the site, which is then built, on pull requests too. Runs on `main` build its tip (`ref: main`) after the release, which has the `index.yaml` chart-releaser just pushed.
- **`website / check`**: Checks the built site's internal links with lychee and every page against WCAG 2.2 A and AA with axe, so a broken or inaccessible site fails the pull request.
- **`pages / deploy`**: On `main`, publishes the build to **GitHub Pages**, which also serves the Helm repository.

## Patches

`patch / update` runs forgejs's `patch.yml` on `webpage/` weekly, on a manual run, and after the `auto-merged` dispatch: OSV-Scanner upgrades the site's vulnerable npm dependencies and commits the result to `main`.

## Dependabot

`merge / review` asks for a review of each Dependabot pull request, as CODEOWNERS doesn't request one on a bot's. `merge / squash` merges it, once every check above has passed or been skipped, then sends the `auto-merged` dispatch, as a merge made with the workflow's token starts no push run on `main`. A GitHub Actions update changes workflow files, which the workflow's token may not merge, so a person merges those.

## Configuration

- **`release.json`** and **`.release.json`**: release-please's configuration (the chart packages and how their changelogs are written) and manifest (each chart's current version).
- **`dependabot.yml`**: keeps the Helm chart dependencies, the npm packages (the root tooling and the `webpage/` site) and the GitHub Actions up to date.
- **`ct.yaml`** (repository root): configuration for `chart-testing`, used by the charts pipeline.
