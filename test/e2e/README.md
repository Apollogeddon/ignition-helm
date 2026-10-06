# Chart e2e on a shared cluster

Scripts for running real gateways from these charts on a shared (e.g. single-node staging) cluster without leaving lasting changes. See `docs/test-plan.md` for the scenarios and coverage.

- `lib.sh`: guardrails, sourced by each scenario
  - `e2e_begin [watch-url]` snapshots cluster-scoped resources, optionally polls a URL every second, and registers teardown plus verification on exit
  - `e2e_ns <name>` creates `chart-e2e-<name>` labelled `e2e=ignition-helm`
  - `e2e_require_memory <ns>` stops unless the node has `E2E_MIN_FREE_MI` (default 4096) MiB available
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
