# Chart test plan and coverage

How the `ignition-failover` and `ignition-scaleout` charts are tested, what each requirement is covered by, and how the tests are kept safe for shared clusters.

## Test layers

| Layer | Where | Covers |
| --- | --- | --- |
| Unit | `charts/*/tests` (helm-unittest, run in CI) | Rendering of every option |
| Staging e2e | `test/e2e` scripts against a shared single-node cluster | Real gateways on Ignition 8.1 and 8.3: health, redundancy, upgrades, ingress, failover timing |
| Script | `test/scripts` (run in CI) | The shell scripts the chart ships (`health-check.sh`, `active-routing.sh`, `certify.sh`), run against stub `curl`/`kubectl` |
| CI e2e | `.github/workflows/.e2e.yml` (`charts / test (staging)`): disposable three-node kind cluster with cert-manager, Contour and Chaos Mesh (manual only; a full run takes about two hours) | The staging scenarios plus what a shared single node can't do safely: network partitions (S10). kind's default CNI enforces NetworkPolicy, which `charts / test (cluster)` already checks |
| Manual | Testing environment | Avi/AKO ingress behaviour |

## Staging guardrails

Staging e2e runs on a shared cluster, so it must leave no lasting or breaking change:

1. Every test runs in its own namespace `chart-e2e-<test>` labelled `e2e=ignition-helm`; nothing is created in existing namespaces.
2. No cluster-scoped changes. Before a run the chart render is checked for cluster-scoped kinds, and a snapshot of cluster-scoped resources (namespaces, CRDs, ClusterRoles/Bindings, webhooks, IngressClasses, PVs, StorageClasses) is taken; after teardown the diff must be empty. Existing services (an ingress controller, cert-manager issuers) are only used, never changed.
3. Resource budget: at most two test gateways at a time with small requests. A run only starts when the node has more than 4Gi of memory available and at least 1Gi of memory not yet promised to other pods' requests, so a test never takes the last schedulable capacity from someone else's rollout.
4. An optional watch URL (a production-like app on the same cluster) is polled every second for the whole run. Every failure is logged with the step the test was on; 3 failures in a row stop the run. With a control (`E2E_WATCH_CONTROL`, e.g. a TCP connect to the node's Talos API port, which does not go through kube-proxy), failures while the control also fails are the test machine's network and are only logged.
5. Teardown always runs; an interrupted session is cleaned with `kubectl delete ns -l e2e=ignition-helm`.

Not done on a shared cluster: replacing the CNI, installing a NetworkPolicy enforcer (it would start enforcing every existing policy), MetalLB (announces LAN addresses), Chaos Mesh (cluster-wide webhooks and privileged agents). These belong in the disposable CI cluster.

## Coverage matrix

Status: **Live** verified on a real deployment, **Unit** helm-unittest only, **Rendered** objects created but behaviour not exercised, **Not tested**, **Gap** the chart does not meet the requirement.

| # | Requirement | Ignition 8.1 | Ignition 8.3 | Notes |
| --- | --- | --- | --- | --- |
| 1 | Install a standalone gateway | Live | Live | |
| 2 | Auto-commission from env (EULA, admin, edition) | Live | Live | |
| 3 | Data kept on the PVC across restarts | Live | Live | |
| 4 | Upgrade from a released chart | Not tested | Live (S02) | a release whose StatefulSets name another Service needs a one-time `--cascade=orphan` delete of them; `activeRouting` goes on in a later, separate upgrade (40); a gateway volume owned by root needs `fixDataOwnership` once (39). See the chart READMEs |
| 5 | No password-resetting preStop | Live | Live | `gwcmd.sh -p` resets the login on 8.1 and 8.3 |
| 6 | Custom lifecycle hooks | Live | Live (CI deploy test) | |
| 7 | Rolling update across a redundant pair in a safe order | Not tested | Live (S06) | with activeRouting, readiness also waits for the Backup to be in sync before the Master is replaced |
| 8 | Health check reflects gateway state | Live | Live | `/StatusPing`; `/main/system/StatusPing` is 404 on 8.3 and redirects to a 404 on 8.1 |
| 9 | Configured probe commands honoured | Live | Live (CI deploy test) | |
| 10 | startupProbe | Live | Live (CI deploy test) | |
| 11 | Uncommissioned gateway not reported healthy | Live (S07) | Live (S07) | readiness (`health-check.sh -r`) fails on `details: COMMISSIONING`; liveness does not, so no restart loop |
| 12 | Master/Backup pairing over GAN TLS, sync Good | Not tested | Live | |
| 13 | Backup takes over when the Master goes away | Not tested | Live | S01: graceful and crash (force delete); a hung Master needs a partition test (CI) |
| 14 | User traffic only reaches the active gateway | Unit | Live (S01 active) | with `activeRouting`, every answered request comes from the Active gateway; off by default, when both Ready pods share the Service |
| 15 | Failover downtime measured | Not tested | Live | S01 with activeRouting, measured from a probe pod in the cluster (every second): graceful 4-5 s unserved, crash 2-3 s; samples from the test machine are coarser and showed 2-3 s for both |
| 16 | Split-brain recovery after a crash | Not tested | CI (S10) | activeRouting keeps traffic on the Master when both report Active; S10 partitions the pair (Chaos Mesh) |
| 17 | PodDisruptionBudget protects the pair | Not tested | Live | |
| 18 | Service (NodePort/ClusterIP/LB) serves traffic | Not tested | Live (NodePort) | LoadBalancer needs MetalLB (CI) |
| 19 | Chart Ingress routes to the gateway | Not tested | Live | S01 via Contour with `ingress.className` |
| 20 | Web TLS (`ssl.enabled`) | Not tested | Live (S05) | |
| 21 | NetworkPolicy and extraIngress enforced | Rendered | CI | `charts / test (cluster)` checks cross-namespace denial on kind (kindnet enforces NetworkPolicy) |
| 22 | Log files cannot grow without bound | Live (S08) | Live (S08) | `logging.wrapperLogToStdout` (default on) appends `wrapper.logfile=/dev/stdout`; no `wrapper.log`, gateway log in `kubectl logs` |
| 23 | Per-logger levels, SQLite limits | Live | Live (CI deploy test) | |
| 24 | emptyDir size limits | Live | Live (CI deploy test) | |
| 25 | GAN certificates issued | Not tested | Live | |
| 26 | GAN rotation CronJob | Not tested | Unit | restartOnRenewal covers renewal, as the init container re-reads certificates on every start |
| 27 | Renewed certificate picked up (restart) | Unit | Live (S06) | `certManager.restartOnRenewal`: rolling restart when the certificate secrets change |
| 29 | Scaleout frontend and backend run | Not tested | Live | |
| 30 | Scaleout frontend connects to backend over GAN | Not tested | Live (S04) | |
| 31 | External modules, ServiceMonitor, restore, local mounts, OnDelete, HPA | Not tested | Unit | |
| 32 | Scaleout Services, PDBs, NetworkPolicies and ServiceMonitors select only their component | Unit | Unit | each selects by `app.kubernetes.io/component` too, so a layer's Service reaches only its own gateways |
| 33 | Probes run the chart's `health-check.sh` | Live | Live | the default command is the script's full path, not the image's own `health-check.sh` on PATH |
| 34 | GAN certificate key rotation policy explicit | Unit | Unit | CA `Never` (keeps signed certificates valid), leaf `Always` |
| 36 | Redundancy peer address follows the chart on every start | Unit (script) | Live (S02) | `seed-redundancy.sh` writes `redundancy.xml` on every start, so a renamed Service's peer names follow |
| 37 | Redundancy role and settings follow values on existing installs (on, off, value changes) | Live (S03) | Live (S03) | `redundancy.xml` is rewritten on every start, and a `checksum/redundancy` annotation restarts the gateways when a value changes |
| 38 | Charts meet the restricted Pod Security level | Live (S07) | Live (S01, S07) | `runAsNonRoot: true` by default (the gateways run as 2003) and a hardened GAN rotation CronJob; S01 and S07 ran in namespaces enforcing `restricted` |
| 39 | Upgrade an install whose data volume is owned by root | n/a | Live (S02) | local-path does not apply `fsGroup`, so the non-root `preconfigure` fails with `Permission denied` on such a volume. Opt-in `fixDataOwnership` chowns the volume once; installs that set `securityContext.runAsUser` (e.g. 2003) are not affected |
| 40 | Upgrade with activeRouting when the StatefulSets name another Service | n/a | Live (S02) | enabling activeRouting in the same upgrade deadlocks: the old Master is only reachable under the old Service name, so the new Backup never syncs and never becomes Ready (the Master keeps serving). Enabling it in a second upgrade works; documented in both READMEs |
| 35 | Scaleout backend named after its pod on the Gateway Network | Unit | Live (S04) | the backend sets `GATEWAY_SYSTEM_NAME`, so each backend gateway takes its pod's name |
| 41 | Restore a gateway backup (`restore`) | Not tested | CI (S09) | the backup is staged once and restored with `-r` on the first start only; a restart keeps the gateway's own changes |

## E2E scenarios

Scripts in `test/e2e` (see its README). Staging runs them on the shared single-node cluster under the guardrails; CI runs them on kind.

| ID | Scenario | Ignition | Where | Covers |
| --- | --- | --- | --- | --- |
| S01 | Ingress plus failover: per-second availability through the Ingress and NodePort while the Master is deleted, then force-deleted; with and without activeRouting | 8.3 | staging, CI | 13, 14, 15, 18, 19 |
| S02 | Upgrade from a released chart (`FROM_VERSION`): failover installed as user 2003 through a wrapper chart, or root-owned with `fixDataOwnership`, and scaleout; activeRouting in a second upgrade | 8.3 | staging, CI | 4, 7, 39, 40 |
| S03 | Redundancy toggle: standalone to pair, a redundancy value change, back to standalone, and re-enabled, with the role and settings applied on restart | 8.1, 8.3 | staging, CI | 37 |
| S04 | Scaleout GAN connection, checked from the gateway logs | 8.3 | staging, CI | 30, 35 |
| S05 | Web TLS with a certificate issued from the chart's CA | 8.3 | staging, CI | 20 |
| S06 | Restart on certificate renewal: Backup restarted before Master | 8.3 | staging, CI | 27 |
| S07 | Uncommissioned gateway never Ready and never restarted | 8.3, 8.1 | staging, CI | 11 |
| S08 | Wrapper log goes to the container log | 8.3, 8.1 | staging, CI | 22 |
| S09 | Restore a gateway backup from a URL on a new install, then a restart keeps a change made after the restore | 8.3 | staging, CI | 41 |
| S10 | Split-brain (Master/Backup partition) and hung Master (Chaos Mesh) | 8.3 | CI only | 13, 15, 16 |

## Results

### S01 ingress and failover with activeRouting (Ignition 8.3, Contour, single node)

Sampled every second from a probe pod in the test namespace (through the -active Service, the NodePort and the ingress controller) as well as from the test machine, which only manages every 2-3 s. "Served" means the request was answered by the Active gateway; `/StatusPing` returns 200 on a cold Backup too, so a 2xx alone does not mean the gateway can serve.

| Phase | In the cluster | From the test machine |
| --- | --- | --- |
| Steady | 65 of 65 s served by the Master | 33 of 33 samples |
| Graceful delete of the Master | 4-5 s unserved | 2 s (`error:503` from the ingress controller while the -active Service was empty) |
| Crash (force delete) | 2-3 s unserved | 2 s |

The pair recovers after the crash, and the scenario passes in a namespace enforcing `restricted` Pod Security too (crash: 3 s unserved in the cluster). On failback the Master takes over again with no overlap. Without activeRouting both Ready pods share the Service, so a cold Backup answers requests it cannot serve.

### S02 upgrades (8.3)

| From | Steps | Result |
| --- | --- | --- |
| A release as user 2003 with its own applicationName | orphan delete, upgrade, then activeRouting in a second upgrade | passed; each step about 350 s; handover gaps 2-6 s |
| A release as user 2003, activeRouting in the same upgrade | orphan delete, one upgrade | **deadlock** (40): the new Backup reports Backup/Unknown/Active because `my-gateway-0.my-gateway-headless` does not resolve for the old pod (its subdomain is still `my-gateway`); the Master keeps serving |
| A release whose volumes are owned by root | orphan delete, upgrade | without `fixDataOwnership` the Backup's `preconfigure` crash-loops (`cp: cannot create regular file '/data/local/metro-keystore': Permission denied`); with it, passed in 352 s, longest gap 3 s |
| A failover release, then activeRouting | orphan delete, upgrade, second upgrade | passed; Backup replaced before the Master in both steps; gaps during the upgrade 3 s or less |
| A scaleout release (one frontend, standalone backend) | orphan delete of both StatefulSets, upgrade | passed; the frontend reconnected to the backend 194 s after the upgrade; 25 s unserved because the only frontend restarts |

Without the orphan delete, `helm upgrade` is rejected, as `spec.serviceName` cannot be changed on a StatefulSet. The orphan step is in both chart READMEs.

### S03 redundancy toggle (8.1 and 8.3)

`seed-redundancy.sh` runs on every start and sets every redundancy key the chart renders (role, peer address, timeouts, recovery mode); with one replica it sets the role to Independent. A `checksum/redundancy` pod annotation restarts the gateways when redundancy values change. All checks pass on both versions:

| Step | 8.1 | 8.3 |
| --- | --- | --- |
| 1. standalone | Independent (Ignition writes its own redundancy.xml as Independent) | same |
| 2. redundancy on | pair formed; longest unserved 1 s; init log: role Independent to Master, peer host set, missing keys added | pair formed; 2 s |
| 3. masterRecoveryMode=Manual | both pods restarted, both files Manual, pair healthy; 1 s | same; 3 s |
| 4. redundancy off | pod 1 removed, pod 0 Master to Independent and still Independent a minute later; 56 s unserved (the only gateway restarts) | same; 48 s |
| 5. redundancy on again (Backup volume kept) | pair formed; 1 s | pair formed; 3 s |

### S04 scaleout Gateway Network (8.3)

The frontend's outgoing connection to the backend goes Faulted while the backend is still starting, then Running once it is up; the backend registers the incoming connection from `ignition-scaleout-frontend-0`, and is named `ignition-scaleout-backend-0` on the Gateway Network.

### S05 web TLS (8.3)

The gateway serves the certificate issued from the chart's CA (`CN=s05-web.e2e.invalid`) on 8043 and reports RUNNING.

### S06 restart on certificate renewal

Redundant pair with activeRouting and restartOnRenewal. After the GAN certificate is re-issued, certify starts a rolling restart: the Backup is replaced, then the Master once the Backup is Ready and in sync, 328 s in all. Through the -active NodePort 208 s were served by the Active gateway and 2 s were not. A further certify run finds the certificates unchanged and restarts nothing.

### S07 uncommissioned gateway

8.1 and 8.3 return `{"state":"RUNNING","details":"COMMISSIONING"}` from `/StatusPing` while the EULA is not accepted. The pod is never Ready over 240 s and never restarted, and its readiness failures read "Gateway is still commissioning", in a namespace enforcing `restricted` Pod Security too. S07 checks the failure reason, so a probe that fails for another reason doesn't pass.

### S08 wrapper log

| Version | wrapperLogToStdout | logs/wrapper.log | kubectl logs (10 min) |
| --- | --- | --- | --- |
| 8.3 | true (default) | none | 305 lines |
| 8.3 | false | 43 KB after start, unrotated | 9 lines |
| 8.1 | true (default) | none | 218 lines |
| 8.1 | false | 27 KB at start-up | 28 lines |

The logs emptyDir then only holds `system_logs.idb` (~70-105 KB).

### Staging notes

- The tunnel to the staging API drops now and then; `kubectl` and `helm` calls are retried on connection errors and installs use `helm upgrade --install` without `--wait`.
- Patching the StatefulSet (certify) shows a PodSecurity `restricted` warning because the `preconfigure` init container sets `runAsNonRoot: false`; a hardening item, not a failure.
- Service and endpoint changes do not make NodePorts drop: a probe pod sampling a test NodePort and the dashboard NodePort every 200 ms saw no failures while Services, and pods behind them, were created and deleted.
- The watch stops a run only after 3 failures in a row, and does not count failures while the control (a TCP connect to the node's Talos API port, which does not go through kube-proxy) also fails. The test machine can lose both the dashboard and the control for 25-55 s around `helm upgrade` together with the cluster API connection; those are logged as the test machine's network and the run carries on.
