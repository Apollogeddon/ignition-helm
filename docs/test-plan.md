# Chart test plan and coverage

How the `ignition-failover` and `ignition-scaleout` charts are tested, what each requirement is covered by, and how the tests are kept safe for shared clusters.

## Test layers

| Layer | Where | Covers |
| --- | --- | --- |
| Unit | `charts/*/tests` (helm-unittest, run in CI) | Rendering of every option |
| Staging e2e | `test/e2e` scripts against a shared single-node cluster | Real gateways on Ignition 8.1 and 8.3: health, redundancy, upgrades, ingress, failover timing |
| Script | `test/scripts` (run in CI) | The shell scripts the chart ships (`health-check.sh`, `active-routing.sh`, `certify.sh`), run against stub `curl`/`kubectl` |
| CI e2e | `.github/workflows/e2e.yaml`: disposable three-node kind cluster with cert-manager, Contour and Chaos Mesh (manual only; a full run takes about two hours) | The staging scenarios plus what a shared single node can't do safely: network partitions (S09). kind's default CNI enforces NetworkPolicy, which `testing.yaml` already checks |
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

| # | Requirement | Ignition 8.1.53 | Ignition 8.3.1 | Notes |
| --- | --- | --- | --- | --- |
| 1 | Install a standalone gateway | Live | Live | |
| 2 | Auto-commission from env (EULA, admin, edition) | Live | Live | |
| 3 | Data kept on the PVC across restarts | Live | Live | |
| 4 | Upgrade from the previous release | Not tested | Live (S02) | from 4.0.0 and 3.1.0 (failover) and 4.0.0 (scaleout): a one-time `--cascade=orphan` delete of the StatefulSets (`serviceName` changed in 4.1.0); `activeRouting` must go on in a later, separate upgrade (fix 40); 3.x installs left on the default root user also need `fixDataOwnership` once (fix 39). See the chart READMEs |
| 5 | No password-resetting preStop | Live | Live | `gwcmd.sh -p` resets the login on 8.1 and 8.3 |
| 6 | Custom lifecycle hooks | Live | Live (CI deploy test) | |
| 7 | Rolling update across a redundant pair in a safe order | Not tested | Live (S06) | with activeRouting, readiness also waits for the Backup to be in sync before the Master is replaced |
| 8 | Health check reflects gateway state | Live | Live | `/StatusPing`; `/main/system/StatusPing` is 404 on 8.3.1 and redirects to a 404 on 8.1 |
| 9 | Configured probe commands honoured | Live | Live (CI deploy test) | |
| 10 | startupProbe | Live | Live (CI deploy test) | |
| 11 | Uncommissioned gateway not reported healthy | Live (S07) | Live (S07) | fixed: readiness (`health-check.sh -r`) fails on `details: COMMISSIONING`; liveness does not, so no restart loop |
| 12 | Master/Backup pairing over GAN TLS, sync Good | Not tested | Live | |
| 13 | Backup takes over when the Master goes away | Not tested | Live | S01: graceful and crash (force delete); a hung Master needs a partition test (CI) |
| 14 | User traffic only reaches the active gateway | Unit | Live (S01 active) | fixed with `activeRouting`: 48 of 49 s served by the Active gateway (was 44%); off by default |
| 15 | Failover downtime measured | Not tested | Live | S01 with activeRouting, measured from a probe pod in the cluster (every second): graceful 4-5 s unserved, crash 2-3 s; samples from the test machine are coarser and showed 2-3 s for both |
| 16 | Split-brain recovery after a crash | Not tested | CI (S09) | activeRouting keeps traffic on the Master when both report Active; S09 partitions the pair (Chaos Mesh) |
| 17 | PodDisruptionBudget protects the pair | Not tested | Live | |
| 18 | Service (NodePort/ClusterIP/LB) serves traffic | Not tested | Live (NodePort) | LoadBalancer needs MetalLB (CI) |
| 19 | Chart Ingress routes to the gateway | Not tested | Live | S01 via Contour with `ingress.className` |
| 20 | Web TLS (`ssl.enabled`) | Not tested | Live (S05) | |
| 21 | NetworkPolicy and extraIngress enforced | Rendered | CI | `testing.yaml` checks cross-namespace denial on kind (kindnet enforces NetworkPolicy) |
| 22 | Log files cannot grow without bound | Live (S08) | Live (S08) | fixed: `logging.wrapperLogToStdout` (default on) appends `wrapper.logfile=/dev/stdout`; no `wrapper.log`, gateway log in `kubectl logs` |
| 23 | Per-logger levels, SQLite limits | Live | Live (CI deploy test) | |
| 24 | emptyDir size limits | Live | Live (CI deploy test) | |
| 25 | GAN certificates issued | Not tested | Live | |
| 26 | GAN rotation CronJob | Not tested | Unit | superseded by restartOnRenewal (the init container re-reads certificates on every start) |
| 27 | Renewed certificate picked up (restart) | Unit | Live (S06) | fixed with `certManager.restartOnRenewal`: rolling restart when the certificate secrets change |
| 29 | Scaleout frontend and backend run | Not tested | Live | |
| 30 | Scaleout frontend connects to backend over GAN | Not tested | Live (S04) | |
| 31 | External modules, ServiceMonitor, restore, local mounts, OnDelete, HPA | Not tested | Unit | |
| 32 | Scaleout Services, PDBs, NetworkPolicies and ServiceMonitors select only their component | Unit | Unit | fixed: all used the same selector, so the frontend Service also sent traffic to backend gateways |
| 33 | Probes run the chart's `health-check.sh` | Live | Live | fixed: the default command was the bare name, which resolves to the Ignition image's own `health-check.sh` on PATH |
| 34 | GAN certificate key rotation policy explicit | Unit | Unit | CA `Never` (keeps signed certificates valid), leaf `Always` |
| 36 | Redundancy peer address follows the chart on every start | Unit (script) | Live (S02) | fixed: `redundancy.xml` was only written on first start, so after the 4.0.0 upgrade both gateways kept peer names that no longer resolved and stayed Active |
| 37 | Redundancy role and settings follow values on existing installs (on, off, value changes) | Live (S03) | Live (S03) | fixed: `redundancy.xml` was only written on first start, so turning redundancy on or off, or changing a redundancy value, did nothing to an existing install (a job driving the Gateway UI was the workaround) |
| 38 | Charts meet the restricted Pod Security level | Live (S07) | Live (S01, S07) | fixed: `runAsNonRoot: true` by default (the gateways already ran as 2003) and a hardened GAN rotation CronJob; S01 and S07 ran in namespaces enforcing `restricted` |
| 39 | Upgrade from a 3.x install that ran the gateway as root | n/a | Live (S02) | 3.1.0 ran everything as root by default, so its data volumes are root-owned and local-path does not apply `fsGroup`; the new non-root `preconfigure` failed with `Permission denied`. Opt-in `fixDataOwnership` chowns the volume once; installs that set `securityContext.runAsUser` (e.g. 2003) are not affected |
| 40 | Upgrade from 4.0.0 or earlier with activeRouting | n/a | Live (S02) | enabling activeRouting in the same upgrade deadlocks: the old Master is only reachable under the old Service name, so the new Backup never syncs and never becomes Ready (the Master keeps serving). Enabling it in a second upgrade works; documented in both READMEs |
| 35 | Scaleout backend named after its pod on the Gateway Network | Unit | Live (S04) | fixed: the backend had no `GATEWAY_SYSTEM_NAME`, so `-n "$(GATEWAY_SYSTEM_NAME)"` stayed literal and every backend gateway had that name |
| 41 | Restore a gateway backup (`restore`) | Not tested | CI (S10) | fixed: the backup was downloaded to the data volume but the gateway was never started with `-r`, so nothing was restored. It is now staged once and restored on the first start only; a restart keeps the gateway's own changes |

## E2E scenarios

Scripts in `test/e2e` (see its README). Staging runs them on the shared single-node cluster under the guardrails; CI runs them on kind.

| ID | Scenario | Ignition | Where | Covers |
| --- | --- | --- | --- | --- |
| S01 | Ingress plus failover: per-second availability through the Ingress and NodePort while the Master is deleted, then force-deleted; with and without activeRouting | 8.3.1 | staging, CI | 13, 14, 15, 18, 19 |
| S02 | Upgrade from a released chart: failover from 4.0.0 or 3.1.0 (as user 2003 through a wrapper chart, or root-owned with `fixDataOwnership`), scaleout from 4.0.0; activeRouting in a second upgrade | 8.3.1 | staging, CI | 4, 7, 39, 40 |
| S03 | Redundancy toggle: standalone to pair, a redundancy value change, back to standalone, and re-enabled, with the role and settings applied on restart | 8.1.53, 8.3.1 | staging, CI | 37 |
| S04 | Scaleout GAN connection, checked from the gateway logs | 8.3.1 | staging, CI | 30, 35 |
| S05 | Web TLS with a certificate issued from the chart's CA | 8.3.1 | staging, CI | 20 |
| S06 | Restart on certificate renewal: Backup restarted before Master | 8.3.1 | staging, CI | 27 |
| S07 | Uncommissioned gateway never Ready and never restarted | 8.3.1, 8.1.53 | staging, CI | 11 |
| S08 | Wrapper log goes to the container log | 8.3.1, 8.1.53 | staging, CI | 22 |
| S09 | Split-brain (Master/Backup partition) and hung Master (Chaos Mesh) | 8.3.1 | CI only | 13, 15, 16 |
| S10 | Restore a gateway backup from a URL on a new install, then a restart keeps a change made after the restore | 8.3.1 | staging, CI | 41 |

## Results

### S01 ingress and failover (Ignition 8.3.1, Contour, single node)

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

### S01 with activeRouting (Ignition 8.3.1, Contour, single node)

| Phase | Served by Active | Notes |
| --- | --- | --- |
| Steady (49 s) | 48 s | one sample timed out; no request reached the cold Backup (was 56%) |
| Graceful delete of Master | 2 s unserved | Backup Active 7 s after the delete; failback went straight to the Master with no overlap |
| Crash (force delete of Master) | 3 s unserved, longest 2 s | Backup Active 7 s after the kill |

Without activeRouting those seconds were "answered" by a cold Backup that could not serve; with it they are honest failures, and every answered request came from the Active gateway.

### S07 uncommissioned gateway

Both versions return `{"state":"RUNNING","details":"COMMISSIONING"}` from `/StatusPing` while the EULA is not accepted. With the fix the pod was never Ready over 240 s and was never restarted, and its readiness failures read "Gateway is still commissioning" on 8.3.1 and 8.1.53.

The first S07 run looked like a pass for the wrong reason: the probe ran the image's own `health-check.sh`, which rejects `-r`. That led to fix 33, and S07 now also checks the failure reason.

### S08 wrapper log

| Version | wrapperLogToStdout | logs/wrapper.log | kubectl logs (10 min) |
| --- | --- | --- | --- |
| 8.3.1 | true (default) | none | 305 lines |
| 8.3.1 | false | 43 KB after start, unrotated | 9 lines |
| 8.1.53 | true (default) | none | 218 lines |

The logs emptyDir then only holds `system_logs.idb` (~70-105 KB).

### Staging notes

- The tunnel to the staging API drops now and then; `kubectl` and `helm` calls are retried on connection errors and installs use `helm upgrade --install` without `--wait`.
- Patching the StatefulSet (certify) shows a PodSecurity `restricted` warning because the `preconfigure` init container sets `runAsNonRoot: false`; a hardening item, not a failure.

### S06 restart on certificate renewal

Redundant pair with activeRouting and restartOnRenewal. After the GAN certificate was re-issued, certify started a rolling restart: Backup replaced at 12:18:41, Master at 12:21:09 (after the Backup was Ready and in sync), 328 s in all. Through the -active NodePort 208 s were served by the Active gateway and 2 s were not. A further certify run found the certificates unchanged and restarted nothing.

### S08 (second run)

Repeated the first run and added 8.1.53 with wrapperLogToStdout=false: wrapper.log reappears (27 KB at start-up) and `kubectl logs` drops to 28 lines.

### S02 upgrade from 4.0.0 (8.3.1)

4.1.0 has been unpublished (its preStop reset the gateway login), so S02 now starts from 4.0.0 with its own probes and runs a plain `helm upgrade`. Three runs:

1. Rejected: `spec.serviceName` changed from `ignition-failover` to `ignition-failover-headless` in 4.1.0 and cannot be changed on a StatefulSet (4.0.0 to 4.1.0 was already broken).
2. With `kubectl delete sts --cascade=orphan` first, the upgrade rolled out but both gateways stayed Active for 12+ minutes: `redundancy.xml` on their volumes still named the peers `ignition-failover-N.ignition-failover`, which no longer resolve, and the chart only wrote it on first start.
3. With `seed-redundancy.sh` now correcting the peer host and port on every start: Backup replaced at 01:46:35, Master at 01:49:02, pair healthy 344 s after the upgrade, longest time without an Active gateway 3 s.

The orphan step is in both chart READMEs ("Upgrading from 4.0.0 or earlier").

### S05 web TLS (8.3.1)

The gateway served the certificate issued from the chart's CA (`CN=s05-web.e2e.invalid`) on 8043 and reported RUNNING.

### S04 scaleout Gateway Network (8.3.1)

The frontend's outgoing connection to the backend went Faulted while the backend was still starting, then Running once it was up; the backend registered the incoming connection from `ignition-scaleout-frontend-0`. The first run showed the backend named `$(gateway_system_name)` on the Gateway Network (fix 35); after the fix it is `ignition-scaleout-backend-0` and S04 passes.

### S03 redundancy toggle (8.1.53 and 8.3.1)

`seed-redundancy.sh` now runs on every start and sets every redundancy key the chart renders (role, peer address, timeouts, recovery mode); with one replica it sets the role to Independent. A `checksum/redundancy` pod annotation restarts the gateways when redundancy values change. All checks passed on both versions:

| Step | 8.1.53 | 8.3.1 |
| --- | --- | --- |
| 1. standalone | Independent (Ignition writes its own redundancy.xml as Independent) | same |
| 2. redundancy on | pair formed; longest unserved 1 s; init log: role Independent to Master, peer host set, missing keys added | pair formed; 2 s |
| 3. masterRecoveryMode=Manual | both pods restarted, both files Manual, pair healthy; 1 s | same; 3 s |
| 4. redundancy off | pod 1 removed, pod 0 Master to Independent and still Independent a minute later; 56 s unserved (the only gateway restarts) | same; 48 s |
| 5. redundancy on again (Backup volume kept) | pair formed; 1 s | pair formed; 3 s |

The run ended on the staging watch guardrail: the dashboard NodePort did not answer in two short bursts (04:05:22-37 and 04:08:42-45, the second with an API connection drop on the test machine). The staging labeller made no routing change and no staging pod restarted, so these were most likely the test machine's network rather than staging.

### S01 with activeRouting and an in-cluster probe

Sampled every second from a probe pod in the test namespace (through the -active Service, the NodePort and the ingress controller) as well as from the test machine, which only managed every 2-3 s:

| Phase | In the cluster | From the test machine |
| --- | --- | --- |
| Steady | 65 of 65 s served by the Master | 33 of 33 samples |
| Graceful delete of the Master | 4-5 s unserved | 2 s (`error:503` from the ingress controller while the -active Service was empty) |
| Crash (force delete) | 2-3 s unserved | 2 s |

The pair recovered after the crash. The same scenario passed again in a namespace enforcing `restricted` Pod Security (crash: 3 s unserved in the cluster).

### S02 upgrades (8.3.1)

| From | Steps | Result |
| --- | --- | --- |
| 3.1.0 as user 2003 with its own applicationName | orphan delete, upgrade, then activeRouting in a second upgrade | passed; each step about 350 s; handover gaps 2-6 s |
| 3.1.0 as user 2003, activeRouting in the same upgrade | orphan delete, one upgrade | **deadlock** (fix 40): the new Backup reported Backup/Unknown/Active for 40 minutes because `my-gateway-0.my-gateway-headless` does not resolve for the old pod (its subdomain is still `my-gateway`); the Master kept serving |
| 3.1.0 with its default root user | orphan delete, upgrade | without `fixDataOwnership` the Backup's `preconfigure` crash-looped (`cp: cannot create regular file '/data/local/metro-keystore': Permission denied`; all 1884 files were root-owned); with it, passed in 352 s, longest gap 3 s |
| 4.0.0, then activeRouting | orphan delete, upgrade, second upgrade | passed; Backup replaced before the Master in both steps; gaps during the upgrade 3 s or less |
| scaleout 4.0.0 (one frontend, standalone backend) | orphan delete of both StatefulSets, upgrade | passed; the frontend reconnected to the backend 194 s after the upgrade; 25 s unserved because the only frontend restarts |

The gateways already on staging run as 2003 (their wrapper chart sets `securityContext`); 495 of 496 files on their volumes are owned by 2003, the other being the data directory itself, created by the provisioner.

### S07 under restricted Pod Security

8.3.1 and 8.1.53: never Ready, never restarted, readiness failing with "Gateway is still commissioning".

### Service churn experiment

Run because the staging dashboard missed checks during test upgrades. A probe pod sampled a test NodePort and the dashboard NodePort every 200 ms:

| Mode | Cycles | In the cluster during churn | From the test machine |
| --- | --- | --- | --- |
| Services created and deleted (no endpoints) | 20 | 0 of 674 samples failed | 0 of 147 |
| a pod added and removed behind the test Service | 20 | 0 of 2056 samples failed | 1 of 438 (both targets at once) |

Service and endpoint changes do not make NodePorts drop. kube-proxy logged nothing while they happened.

### Staging watch guardrail

The watch now stops a run only after 3 failures in a row, and does not count failures while the control (a TCP connect to the node's Talos API port, which does not go through kube-proxy) also fails. Three times the test machine lost both the dashboard and the control for 25-55 s, each time within seconds of `helm upgrade` starting and together with the cluster API connection; all were logged as the test machine's network and the runs carried on. The one counted miss (a single sample during an S01 crash) did not repeat. Nothing points at staging itself.

### Not yet run

S09 and the CI workflow: they run on GitHub once `main` is pushed (start E2E manually from Actions).
