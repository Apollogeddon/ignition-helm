#!/usr/bin/env bash
# Runs the chart's certify.sh against a stub kubectl and checks when it
# restarts a StatefulSet. Usage: test/scripts/certify_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" --show-only templates/configmap-scripts.yaml |
  awk '/^  certify.sh: \|-/ {on=1; next} on && /^  [^ ]/ {on=0} on {sub(/^    /, ""); print}' > "$work/certify.sh"
[ -s "$work/certify.sh" ] || { echo "could not extract certify.sh"; exit 1; }

mkdir "$work/bin"
# kubectl stub: secrets from $SECRET_<name>, the StatefulSet hash annotation
# from $HASH (unset = StatefulSet missing), rollout status from $STATUS;
# annotate/rollout calls are recorded in $CALLS
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "get secret") var="SECRET_${3//-/_}"; [ -n "${!var:-}" ] || exit 1; printf '%s' "${!var}" ;;
  "get statefulset")
    [ -n "${HASH+x}" ] || exit 1
    case "$*" in
      *certify-hash*) printf '%s' "$HASH" ;;
      *) printf '%s' "${STATUS:-2/2/2/r1/r1}" ;;
    esac ;;
  "annotate statefulset") echo "annotate $3 ${6#certify-hash=}" >> "$CALLS" ;;
  "rollout restart") echo "restart $4" >> "$CALLS" ;;
esac
STUB
chmod +x "$work/bin/kubectl"

fails=0
# run <env...>: run certify.sh once; sets $rc and $calls
run() {
  : > "$work/calls"
  env PATH="$work/bin:$PATH" CALLS="$work/calls" NAMESPACE=ns TARGETS="gw=gw-ca,gw-tls" \
    SECRET_gw_ca='{"ca.crt":"QQ=="}' SECRET_gw_tls='{"tls.crt":"Qg=="}' "$@" sh "$work/certify.sh" > /dev/null
  rc=$?
  calls=$(paste -sd'|' "$work/calls")
}
# check <description> <expected exit> <expected calls (regex)>
check() {
  if [ "$rc" -eq "$2" ] && [[ "$calls" =~ ^$3$ ]]; then echo "ok   $1"
  else echo "FAIL $1 (exit $rc, calls '$calls')"; fails=$((fails + 1)); fi
}

run HASH=
check "first run records the hash without restarting" 0 "annotate gw [0-9a-f]{16}"
hash=${calls##* }

run HASH="$hash"
check "unchanged certificates do nothing" 0 ""

run HASH="$hash" SECRET_gw_tls='{"tls.crt":"Qw=="}'
check "renewed certificate restarts and records the new hash" 0 "restart gw\|annotate gw [0-9a-f]{16}"
[ "${calls##* }" != "$hash" ] || { echo "FAIL new hash equals old hash"; fails=$((fails + 1)); }

run HASH="$hash" SECRET_gw_tls='{"tls.crt":"Qw=="}' STATUS="2/1/1/r1/r2"
check "waits while a rollout is in progress" 0 ""

run HASH="$hash" SECRET_gw_ca=
check "missing secret is reported and skipped" 1 ""

run SECRET_gw_tls='{"tls.crt":"Qw=="}'
check "missing StatefulSet is reported and skipped" 1 ""

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
