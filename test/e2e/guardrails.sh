#!/usr/bin/env bash
# guardrails.sh [watch-url]: self-test of the guardrails; creates one e2e
# namespace, checks free memory and the render check, then tears down and verifies
source "$(dirname "$0")/lib.sh"
e2e_begin "${1:-}"
ns=$(e2e_ns guardrails)
e2e_require_memory "$ns"
e2e_render_check "$(dirname "$0")/../../charts/failover" -n "$ns"
log "render check passed"
e2e_watch_check
