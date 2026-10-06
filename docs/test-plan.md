# Chart test plan and coverage

How the `ignition-failover` and `ignition-scaleout` charts are tested, what each requirement is covered by, and how the tests are kept safe for shared clusters.

## Test layers

| Layer | Where | Covers |
| --- | --- | --- |
| Unit | `charts/*/tests` (helm-unittest, run in CI) | Rendering of every option |
| Staging e2e | `test/e2e` scripts against a shared single-node cluster | Real gateways on Ignition 8.1 and 8.3: health, redundancy, upgrades, ingress, failover timing |
| CI e2e (planned) | GitHub Actions, disposable kind cluster | Things a shared single node can't do safely: enforced NetworkPolicy (Calico), node loss (multi-node kind), LoadBalancer (MetalLB), network partitions (Chaos Mesh) |
| Manual | Testing environment / vendor | Avi/AKO ingress behaviour; licence binding to the machine ID |

## Staging guardrails

Staging e2e runs on a shared cluster, so it must leave no lasting or breaking change:

1. Every test runs in its own namespace `chart-e2e-<test>` labelled `e2e=ignition-helm`; nothing is created in existing namespaces.
2. No cluster-scoped changes. Before a run the chart render is checked for cluster-scoped kinds, and a snapshot of cluster-scoped resources (namespaces, CRDs, ClusterRoles/Bindings, webhooks, IngressClasses, PVs, StorageClasses) is taken; after teardown the diff must be empty. Existing services (an ingress controller, cert-manager issuers) are only used, never changed.
3. Resource budget: at most two test gateways at a time with small requests, and a run only starts when the node has more than 4Gi of memory available.
4. An optional watch URL (a production-like app on the same cluster) is polled every second for the whole run; any failure stops the run.
5. Teardown always runs; an interrupted session is cleaned with `kubectl delete ns -l e2e=ignition-helm`.

Not done on a shared cluster: replacing the CNI, installing a NetworkPolicy enforcer (it would start enforcing every existing policy), MetalLB (announces LAN addresses), Chaos Mesh (cluster-wide webhooks and privileged agents). These belong in the disposable CI cluster.

## Coverage matrix

Status: **Live** verified on a real deployment, **Unit** helm-unittest only, **Rendered** objects created but behaviour not exercised, **Not tested**, **Gap** the chart does not meet the requirement.

| # | Requirement | Ignition 8.1.53 | Ignition 8.3.1 | Notes |
| --- | --- | --- | --- | --- |
| 1 | Install a standalone gateway | Live | Live | |
| 2 | Auto-commission from env (EULA, admin, edition) | Live | Live | |
| 3 | Data kept on the PVC across restarts | Live | Live | |
| 4 | Upgrade from the previous release | Not tested | Live (single) | redundant upgrade pending |
| 5 | No password-resetting preStop | Live | Live | `gwcmd.sh -p` resets the login on 8.1 and 8.3 |
| 6 | Custom lifecycle hooks | Live | Unit | |
| 7 | Rolling update across a redundant pair in a safe order | Not tested | Not tested | |
| 8 | Health check reflects gateway state | Live | Live | `/StatusPing`; `/main/system/StatusPing` is 404 on 8.3.1 and redirects to a 404 on 8.1 |
| 9 | Configured probe commands honoured | Live | Unit | |
| 10 | startupProbe | Live | Unit | |
| 11 | Uncommissioned gateway not reported healthy | Gap | Gap | `/StatusPing` reports RUNNING with `details: COMMISSIONING` |
| 12 | Master/Backup pairing over GAN TLS, sync Good | Not tested | Live | |
| 13 | Backup takes over when the Master goes away | Not tested | Live (graceful) | crash pending |
| 14 | User traffic only reaches the active gateway | Gap | Gap | default readiness passes on a cold Backup, so the Service routes to it |
| 15 | Failover downtime measured | Not tested | Not tested | |
| 16 | Split-brain recovery after a crash | Gap | Not tested | |
| 17 | PodDisruptionBudget protects the pair | Not tested | Live | |
| 18 | Service (NodePort/ClusterIP/LB) serves traffic | Not tested | Rendered | |
| 19 | Chart Ingress routes to the gateway | Not tested | Not tested | unit tests exist |
| 20 | Web TLS (`ssl.enabled`) | Not tested | Not tested | |
| 21 | NetworkPolicy and extraIngress enforced | Rendered | Rendered | needs an enforcing CNI (CI) |
| 22 | Log files cannot grow without bound | Gap | Gap | `wrapper.log` is written unrotated to the logs emptyDir unless `wrapper.logfile=/dev/stdout` is passed |
| 23 | Per-logger levels, SQLite limits | Live | Unit | |
| 24 | emptyDir size limits | Live | Unit | |
| 25 | GAN certificates issued | Not tested | Live | |
| 26 | GAN rotation CronJob | Not tested | Unit | |
| 27 | Renewed certificate picked up (restart) | Gap | Gap | rotation rewrites the keystore without a restart |
| 28 | Stable machine ID via extraVolumes | Not tested | Not tested | |
| 29 | Scaleout frontend and backend run | Not tested | Live | |
| 30 | Scaleout frontend connects to backend over GAN | Not tested | Not tested | |
| 31 | External modules, ServiceMonitor, restore, local mounts, OnDelete, HPA | Not tested | Unit | |

## Staging e2e scenarios

| ID | Scenario | Ignition | Covers |
| --- | --- | --- | --- |
| S1 | Ingress plus failover: chart Ingress, per-second availability through the Ingress and NodePort while the Master is deleted, then killed | 8.3.1 | 13, 14, 15, 18, 19 |
| S2 | Redundant upgrade from the previous release | 8.3.1 | 4, 7 |
| S3 | Machine ID via a Secret mounted with extraVolumes | 8.1.53 | 28 |
| S4 | Scaleout GAN connection | 8.3.1 | 30 |
| S5 | Web TLS with a self-signed certificate | 8.3.1 | 20 |
| S6 | GAN rotation CronJob triggered manually | 8.3.1 | 26 |
| S7 | New options on 8.3 | 8.3.1 | 6, 9, 10, 23, 24 |
