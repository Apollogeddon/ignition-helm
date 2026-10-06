# Chart test plan and coverage

How the `ignition-failover` and `ignition-scaleout` charts are tested, what each requirement is covered by, and how the tests are kept safe for shared clusters.

## Test layers

| Layer | Where | Covers |
| --- | --- | --- |
| Unit | `charts/*/tests` (helm-unittest, run in CI) | Rendering of every option |
| Staging e2e | `test/e2e` scripts against a shared single-node cluster | Real gateways on Ignition 8.1 and 8.3: health, redundancy, upgrades, ingress, failover timing |
| Script | `test/scripts` (run in CI) | The shell scripts the chart ships (`health-check.sh`, `active-routing.sh`, `certify.sh`), run against stub `curl`/`kubectl` |
| CI e2e | `.github/workflows/e2e.yaml`: disposable three-node kind cluster with cert-manager, Contour and Chaos Mesh (manual or weekly) | The staging scenarios plus what a shared single node can't do safely: network partitions (S10). kind's default CNI enforces NetworkPolicy, which `testing.yaml` already checks |
| Manual | Testing environment / vendor | Avi/AKO ingress behaviour; licence binding to the machine ID |

## Staging guardrails

Staging e2e runs on a shared cluster, so it must leave no lasting or breaking change:

1. Every test runs in its own namespace `chart-e2e-<test>` labelled `e2e=ignition-helm`; nothing is created in existing namespaces.
2. No cluster-scoped changes. Before a run the chart render is checked for cluster-scoped kinds, and a snapshot of cluster-scoped resources (namespaces, CRDs, ClusterRoles/Bindings, webhooks, IngressClasses, PVs, StorageClasses) is taken; after teardown the diff must be empty. Existing services (an ingress controller, cert-manager issuers) are only used, never changed.
3. Resource budget: at most two test gateways at a time with small requests. A run only starts when the node has more than 4Gi of memory available and at least 1Gi of memory not yet promised to other pods' requests, so a test never takes the last schedulable capacity from someone else's rollout.
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
| 7 | Rolling update across a redundant pair in a safe order | Not tested | S2 | with activeRouting, readiness also waits for the Backup to be in sync before the Master is replaced |
| 8 | Health check reflects gateway state | Live | Live | `/StatusPing`; `/main/system/StatusPing` is 404 on 8.3.1 and redirects to a 404 on 8.1 |
| 9 | Configured probe commands honoured | Live | Unit | |
| 10 | startupProbe | Live | Unit | |
| 11 | Uncommissioned gateway not reported healthy | Live (S8) | Live (S8) | fixed: readiness (`health-check.sh -r`) fails on `details: COMMISSIONING`; liveness does not, so no restart loop |
| 12 | Master/Backup pairing over GAN TLS, sync Good | Not tested | Live | |
| 13 | Backup takes over when the Master goes away | Not tested | Live | S1: graceful and crash (force delete); a hung Master needs a partition test (CI) |
| 14 | User traffic only reaches the active gateway | Unit | Live (S1 active) | fixed with `activeRouting`: 48 of 49 s served by the Active gateway (was 44%); off by default |
| 15 | Failover downtime measured | Not tested | Live | S1 with activeRouting: 2-3 s unserved for graceful and crash failover; failback switches straight to the Master |
| 16 | Split-brain recovery after a crash | Not tested | CI (S10) | activeRouting keeps traffic on the Master when both report Active; S10 partitions the pair (Chaos Mesh) |
| 17 | PodDisruptionBudget protects the pair | Not tested | Live | |
| 18 | Service (NodePort/ClusterIP/LB) serves traffic | Not tested | Live (NodePort) | LoadBalancer needs MetalLB (CI) |
| 19 | Chart Ingress routes to the gateway | Not tested | Live | S1 via Contour with `ingress.className` |
| 20 | Web TLS (`ssl.enabled`) | Not tested | Not tested | |
| 21 | NetworkPolicy and extraIngress enforced | Rendered | CI | `testing.yaml` checks cross-namespace denial on kind (kindnet enforces NetworkPolicy) |
| 22 | Log files cannot grow without bound | Live (S9) | Live (S9) | fixed: `logging.wrapperLogToStdout` (default on) appends `wrapper.logfile=/dev/stdout`; no `wrapper.log`, gateway log in `kubectl logs` |
| 23 | Per-logger levels, SQLite limits | Live | Unit | |
| 24 | emptyDir size limits | Live | Unit | |
| 25 | GAN certificates issued | Not tested | Live | |
| 26 | GAN rotation CronJob | Not tested | Unit | superseded by restartOnRenewal (the init container re-reads certificates on every start) |
| 27 | Renewed certificate picked up (restart) | Unit | S6 | fixed with `certManager.restartOnRenewal`: rolling restart when the certificate secrets change |
| 28 | Stable machine ID via extraVolumes | Not tested | Not tested | |
| 29 | Scaleout frontend and backend run | Not tested | Live | |
| 30 | Scaleout frontend connects to backend over GAN | Not tested | Not tested | |
| 31 | External modules, ServiceMonitor, restore, local mounts, OnDelete, HPA | Not tested | Unit | |
| 32 | Scaleout Services, PDBs, NetworkPolicies and ServiceMonitors select only their component | Unit | Unit | fixed: all used the same selector, so the frontend Service also sent traffic to backend gateways |
| 33 | Probes run the chart's `health-check.sh` | Live | Live | fixed: the default command was the bare name, which resolves to the Ignition image's own `health-check.sh` on PATH |
| 34 | GAN certificate key rotation policy explicit | Unit | Unit | CA `Never` (keeps signed certificates valid), leaf `Always` |

## E2E scenarios

Scripts in `test/e2e` (see its README). Staging runs them on the shared single-node cluster under the guardrails; CI runs them on kind.

| ID | Scenario | Ignition | Where | Covers |
| --- | --- | --- | --- | --- |
| S1 | Ingress plus failover: per-second availability through the Ingress and NodePort while the Master is deleted, then force-deleted; with and without activeRouting | 8.3.1 | staging, CI | 13, 14, 15, 18, 19 |
| S2 | Redundant upgrade from the released chart, with and without activeRouting | 8.3.1 | staging, CI | 4, 7 |
| S3 | Machine ID from a ConfigMap via extraVolumes, kept across pod replacement | 8.1.53 | staging, CI | 28 |
| S4 | Scaleout GAN connection | 8.3.1 | not written yet | 30 |
| S5 | Web TLS with a certificate issued from the chart's CA | 8.3.1 | staging, CI | 20 |
| S6 | Restart on certificate renewal: Backup restarted before Master | 8.3.1 | staging, CI | 27 |
| S7 | Lifecycle, custom readiness, startupProbe, loggers, SQLite and emptyDir limits together | 8.3.1 | staging, CI | 6, 9, 10, 23, 24 |
| S8 | Uncommissioned gateway never Ready and never restarted | 8.3.1, 8.1.53 | staging, CI | 11 |
| S9 | Wrapper log goes to the container log | 8.3.1, 8.1.53 | staging, CI | 22 |
| S10 | Split-brain (Master/Backup partition) and hung Master (Chaos Mesh) | 8.3.1 | CI only | 13, 15, 16 |

## Results

### S1 ingress and failover (Ignition 8.3.1, Contour, single node)

Per-second samples through the Ingress. "Served" means the request was answered by the Active gateway; `/StatusPing` returns 200 on a cold Backup too, so a 2xx alone does not mean the gateway can serve.

| Phase | Ingress 2xx | Served by Active | Notes |
| --- | --- | --- | --- |
| Steady (60s) | 100% | 44% | both pods Ready, so the Service balances across them and 56% of requests reach the cold Backup (#14) |
| Graceful delete of Master | 100% | no gap at failover | Backup Active within 2s of the delete; Master took back over after ~2.5 min |
| Crash (force delete of Master) | 100% | ~3s gap | Backup Active ~3s after the kill; detection is fast because the dead pod's connections close |

Other observations:

- On failback both gateways report Active for up to ~10s before the Backup returns to Cold.
- cert-manager 1.18+ warns that `privateKey.rotationPolicy` now defaults to `Always` on the GAN certificates; the chart should set it explicitly.
- Staging watch URL: no failures. Cluster-scoped resources unchanged after teardown.

### S1 with activeRouting (Ignition 8.3.1, Contour, single node)

| Phase | Served by Active | Notes |
| --- | --- | --- |
| Steady (49 s) | 48 s | one sample timed out; no request reached the cold Backup (was 56%) |
| Graceful delete of Master | 2 s unserved | Backup Active 7 s after the delete; failback went straight to the Master with no overlap |
| Crash (force delete of Master) | 3 s unserved, longest 2 s | Backup Active 7 s after the kill |

Without activeRouting those seconds were "answered" by a cold Backup that could not serve; with it they are honest failures, and every answered request came from the Active gateway.

### S8 uncommissioned gateway

Both versions return `{"state":"RUNNING","details":"COMMISSIONING"}` from `/StatusPing` while the EULA is not accepted. With the fix the pod was never Ready over 240 s and was never restarted, and its readiness failures read "Gateway is still commissioning" on 8.3.1 and 8.1.53.

The first S8 run looked like a pass for the wrong reason: the probe ran the image's own `health-check.sh`, which rejects `-r`. That led to fix 33, and S8 now also checks the failure reason.

### S9 wrapper log

| Version | wrapperLogToStdout | logs/wrapper.log | kubectl logs (10 min) |
| --- | --- | --- | --- |
| 8.3.1 | true (default) | none | 305 lines |
| 8.3.1 | false | 43 KB after start, unrotated | 9 lines |
| 8.1.53 | true (default) | none | 218 lines |

The logs emptyDir then only holds `system_logs.idb` (~70-105 KB).

### Staging notes

- The tunnel to the staging API drops now and then; `kubectl` and `helm` calls are retried on connection errors and installs use `helm upgrade --install` without `--wait`.
- Patching the StatefulSet (certify) shows a PodSecurity `restricted` warning because the `preconfigure` init container sets `runAsNonRoot: false`; a hardening item, not a failure.
