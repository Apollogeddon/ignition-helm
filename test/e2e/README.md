# Chart e2e on a shared cluster

Scripts for running real gateways from these charts on a shared (e.g. single-node staging) cluster without leaving lasting changes. See `docs/test-plan.md` for the scenarios and coverage.

- `lib.sh`: guardrails, sourced by each scenario
  - `e2e_begin [watch-url]` snapshots cluster-scoped resources, optionally polls a URL every second, and registers teardown plus verification on exit
  - `e2e_ns <name>` creates `chart-e2e-<name>` labelled `e2e=ignition-helm`
  - `e2e_require_memory <ns>` stops unless the node has `E2E_MIN_FREE_MI` (default 4096) MiB available and some node can still schedule `E2E_MIN_REQUEST_MI` (default 1024) MiB of requests
  - `e2e_render_check <helm template args>` refuses a render containing cluster-scoped kinds
  - `e2e_watch_check` stops the run if the watched URL has failed
- `record.sh <seconds> <out> name=url...`: per-second availability log; `/system/gwinfo` URLs log the redundancy role and state that answered
- `values/small.yaml`: small requests so test gateways fit beside other workloads
- `guardrails.sh [watch-url]`: self-test of the guardrails

Environment: `HELM` (helm binary), `E2E_OUT` (results directory, default `./e2e-out`), `E2E_PROBE_IMAGE` (default `busybox:1.36`).

Build chart dependencies first (`helm dependency build charts/failover`). If a run is interrupted, clean up with:

```sh
kubectl delete ns -l e2e=ignition-helm
```

## Scenarios

- `s1-ingress-failover.sh`: redundant pair behind the chart Ingress; records availability through the Ingress and NodePort, and which gateway answered, while the Master is deleted and then force-deleted (crash). Needs `NODE_IP` and `INGRESS_PORT` (the ingress controller's HTTP NodePort); optional `INGRESS_CLASS` (default `contour`), `WATCH_URL`, `IMAGE_TAG`.
- `s8-uncommissioned.sh`: a gateway that cannot finish commissioning (EULA not accepted) must never become Ready and must not be restarted by liveness; runs on each of `IMAGE_TAGS` (default `8.3.1 8.1.53`) and records the `/StatusPing` bodies.
- `s6-restart-on-renewal.sh`: redundant pair with `activeRouting` and `restartOnRenewal`; the first certify run only records the certificate hash, a renewal (GAN TLS secret deleted and re-issued) triggers a rolling restart with the Backup replaced before the Master, and a further run does nothing. Records availability through the `-active` NodePort. Needs `NODE_IP`.
- `s9-wrapper-log.sh`: for each of `IMAGE_TAGS`, checks that with the default `wrapperLogToStdout` the gateway log reaches `kubectl logs` and `logs/wrapper.log` does not grow, and records the same with it turned off for comparison.
- `s10-partition.sh` (disposable clusters only, needs Chaos Mesh): partitions the Master from the Backup (split-brain) and then isolates the Master entirely (hung Master); checks traffic is never routed to two gateways, measures the unserved time, and checks the pair settles afterwards.

CI runs these on a disposable kind cluster with `.github/workflows/e2e.yaml` (manual only; a full run takes about two hours); `.github/scripts/e2e/setup-cluster.sh` installs cert-manager, Contour and Chaos Mesh.
- `s2-upgrade.sh`: installs a redundant pair from a released version (`FROM_VERSION`, default 4.1.0, with its probes off because they never pass on 8.3) and upgrades it to the working tree (`UPGRADE_SET` adds values, e.g. `ignition.activeRouting.enabled=true`); checks the Backup is replaced before the Master and the pair recovers, and records the unserved time. Needs `NODE_IP`.
- `s3-machine-id.sh`: mounts a machine ID from a ConfigMap with `extraVolumes`/`extraVolumeMounts` (default image 8.1.53) and checks the gateway runs with it and keeps it after the pod is replaced.
- `s5-web-tls.sh`: `ssl.enabled` with a PKCS#12 web certificate issued in the test namespace by the chart's GAN CA Issuer; checks the gateway serves it on 8043 and is RUNNING.
- `s7-options.sh`: postStart lifecycle hook, custom readiness command, startupProbe, per-logger levels, SQLite limits and emptyDir size limits together; checks each is in effect and the gateway is Ready without restarts.
- `s4-scaleout-gan.sh`: one scaleout frontend and a standalone backend; checks from the gateway logs that the frontend's Gateway Network connection to the backend reaches Running, the backend registers it, and no gateway is named by an unexpanded `$(GATEWAY_SYSTEM_NAME)`.
