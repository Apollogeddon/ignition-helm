#!/usr/bin/env bash
# Checks the redundancy, active-routing, module, issuer and rollout checks in
# test/e2e/lib.sh that S11 (and others) use, against canned gwinfo bodies,
# gateway logs and a stub kubectl. Usage: test/scripts/e2e-checks_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# the stub answers from files in $STUB: gwinfo-<pod> for an exec, <kind>.out for a get
mkdir "$work/bin" "$work/stub"
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
a=" $* "
case "$a" in
  # exec <pod> ...: the pod's canned gwinfo body, or nothing (no answer)
  *" exec "*) p=${a#* exec }; cat "$STUB/gwinfo-${p%% *}" 2>/dev/null; exit 0 ;;
esac
for k in endpointslices clusterissuer issuer statefulset pods; do
  case "$a" in *" get $k "*) [ -f "$STUB/$k.out" ] || exit 1; cat "$STUB/$k.out"; exit 0 ;; esac
done
exit 1
STUB
chmod +x "$work/bin/kubectl"

fails=0
# run <snippet>: run a snippet with lib.sh sourced and the stub kubectl first on PATH
run() {
  ( export PATH="$work/bin:$PATH" STUB="$work/stub" E2E_OUT="$work/out"
    source "$root/test/e2e/lib.sh"; eval "$1" ) 2>/dev/null
}
# check <description> <want exit> <snippet>
check() {
  local status=0
  run "$3" > /dev/null || status=$?
  [ "$status" -eq 0 ] || status=1
  if [ "$status" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (exit $status, want $2)"; fails=$((fails + 1)); fi
}
# equal <description> <want output> <snippet>
equal() {
  local got
  got=$(run "$3")
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$got', want '$2')"; fails=$((fails + 1)); fi
}

MASTER="ContextStatus=RUNNING;PlatformName=g-0;Version=8.3.10;RedundancyStatus=Master;RedundantState=Good;RedundantNodeActiveStatus=Active;OS=Linux;"
BACKUP="ContextStatus=RUNNING;PlatformName=g-1;Version=8.3.10;RedundancyStatus=Backup;RedundantState=Good;RedundantNodeActiveStatus=Cold;OS=Linux;"

equal "gwinfo summary" "Master/Good/Active" "e2e_gwinfo_summary <<< '$MASTER'"
equal "gwinfo summary of a standalone gateway is empty" "" "e2e_gwinfo_summary <<< 'ContextStatus=RUNNING;Version=8.3.10;'"
printf '%s' "$MASTER" > "$work/stub/gwinfo-g-0"
printf '%s' "$BACKUP" > "$work/stub/gwinfo-g-1"
equal "gwinfo from a pod" "Backup/Good/Cold" "e2e_gwinfo ns g-1"
equal "gwinfo field from a pod" "8.3.10" "e2e_gwinfo ns g-0 Version"
equal "no gwinfo answer is empty" "" "e2e_gwinfo ns g-9"

check "a Good pair is healthy" 0 "e2e_pair_good Master/Good/Active Backup/Good/Cold"
check "an Incompatible Backup is not healthy" 1 "e2e_pair_good Master/Modules_Incompatible/Active Backup/Incompatible/Cold"
check "a Master that is not Good is not healthy" 1 "e2e_pair_good Master/Unknown/Active Backup/Good/Cold"
check "an Active Backup is not healthy" 1 "e2e_pair_good Master/Good/Active Backup/Good/Active"
check "a missing answer is not healthy" 1 "e2e_pair_good Master/Good/Active ''"
check "wait_pair returns once the pair is Good" 0 "e2e_wait_pair ns g 30"
printf '%s' "${BACKUP/Good/OutOfDate}" > "$work/stub/gwinfo-g-1"
check "wait_pair fails while the Backup is not Good" 1 "e2e_wait_pair ns g 1"

# active routing: the labelled pods and the -active Service's endpoints
printf 'g-0\n' > "$work/stub/pods.out"; printf 'g-0\n' > "$work/stub/endpointslices.out"
check "the Master labelled and the only endpoint passes" 0 "e2e_active_check ns g"
printf 'g-1\n' > "$work/stub/pods.out"; printf 'g-1\n' > "$work/stub/endpointslices.out"
check "the Backup labelled fails" 1 "e2e_active_check ns g"
printf 'g-0\ng-1\n' > "$work/stub/pods.out"; printf 'g-0\n' > "$work/stub/endpointslices.out"
check "both labelled fails" 1 "e2e_active_check ns g"
printf '' > "$work/stub/pods.out"
check "no label fails" 1 "e2e_active_check ns g"
printf 'g-0\n' > "$work/stub/pods.out"; printf '' > "$work/stub/endpointslices.out"
check "no endpoint fails" 1 "e2e_active_check ns g"
printf 'g-0\ng-1\n' > "$work/stub/endpointslices.out"
check "a second endpoint fails" 1 "e2e_active_check ns g"

# modules: the gateway log names each module it starts
cat > "$work/gateway.log" <<'LOG'
jvm 1    | 2026/11/26 06:23:43 | I [ModuleInstance                ] [06:23:43.178]: Starting up module 'com.inductiveautomation.jdbc.mariadb' v1.3.10 (b2026100610)... module-name=MariaDB JDBC Driver
jvm 1    | 2026/11/26 06:23:43 | I [ModuleInstance                ] [06:23:43.178]: Starting up module 'com.inductiveautomation.jdbc.postgresql' v1.3.10 (b2026100610)... module-name=PostgreSQL JDBC Driver
LOG
check "started modules pass" 0 "e2e_modules_started '$work/gateway.log' com.inductiveautomation.jdbc.postgresql com.inductiveautomation.jdbc.mariadb"
equal "a module that did not start is named" "com.inductiveautomation.jdbc.mssql" \
  "e2e_modules_started '$work/gateway.log' com.inductiveautomation.jdbc.postgresql com.inductiveautomation.jdbc.mssql"
check "a module that did not start fails" 1 "e2e_modules_started '$work/gateway.log' com.inductiveautomation.jdbc.mssql"
check "a module id is not a prefix match" 1 "e2e_modules_started '$work/gateway.log' com.inductiveautomation.jdbc"

# issuers: only the CA type passes
printf 'cluster-ca' > "$work/stub/clusterissuer.out"
check "a CA ClusterIssuer passes" 0 "e2e_issuer_is_ca ns ClusterIssuer ca"
printf '' > "$work/stub/clusterissuer.out"
check "a self-signed ClusterIssuer fails" 1 "e2e_issuer_is_ca ns ClusterIssuer self"
rm "$work/stub/clusterissuer.out"
check "a missing ClusterIssuer fails" 1 "e2e_issuer_is_ca ns ClusterIssuer none"
printf 's11-ca' > "$work/stub/issuer.out"
check "a CA Issuer passes" 0 "e2e_issuer_is_ca ns Issuer s11-ca"

# rollout: replicas/ready/updated/currentRevision/updateRevision
printf '2/2/2/r2/r2' > "$work/stub/statefulset.out"
check "a finished rolling update passes" 0 "e2e_rollout_done ns g"
printf '2/1/1/r1/r2' > "$work/stub/statefulset.out"
check "a rolling update stuck on the Backup fails" 1 "e2e_rollout_done ns g"
printf '2/2/2/r1/r2' > "$work/stub/statefulset.out"
check "a rolling update that has not switched revision fails" 1 "e2e_rollout_done ns g"
printf '2//2/r2/r2' > "$work/stub/statefulset.out"
check "no Ready replicas fails" 1 "e2e_rollout_done ns g"
rm "$work/stub/statefulset.out"
check "a missing StatefulSet fails" 1 "e2e_rollout_done ns g"

# memory quantities (e2e_require_memory), with the system awk, which may be mawk
equal "memory quantities sum in MiB" "1537" "printf '1Gi\\n512Mi\\n1024Ki\\n' | e2e_to_mi"
equal "decimal memory quantities" "1907" "printf '1G\\n1000M\\n' | e2e_to_mi"

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
