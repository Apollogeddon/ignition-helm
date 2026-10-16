# Security policy

## Supported versions

Only the latest release of each chart receives security fixes.

## Reporting a vulnerability

Report security vulnerabilities privately using [GitHub's private vulnerability reporting](https://github.com/Apollogeddon/ignition-helm/security/advisories/new) rather than opening a public issue.

You should expect an initial response within a few days. If the issue is confirmed, a fix is released as a patch version of the affected charts and credited in the advisory unless you request otherwise.

## Verifying the charts

Every chart release carries a Sigstore bundle that cosign made keyless in the release pipeline (`version / release`), before the release was published. See [Verifying a chart](../README.md#verifying-a-chart) for the command that checks a downloaded chart against it.

## Automated security tooling

This repository runs the following on every change:

- **Gitleaks**: scans the repository for committed secrets
- **Trivy**, **kube-linter** and **Checkov**: scan the rendered charts for vulnerabilities and misconfigurations
- **OSV-Scanner**: scans the documentation site's dependencies for known vulnerabilities
- **Dependabot**: with a 3-day cooldown before new dependency versions are proposed, giving time for a compromised release to be caught and yanked upstream
