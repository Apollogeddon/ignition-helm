#!/usr/bin/env bash
# Runs test/e2e/record.sh against a stub curl and checks how each kind of reply
# is labelled (two-second runs: a one-second run can end before its first
# sample). Usage: test/scripts/record_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
# curl: the host part of the URL picks the reply: BODY_<host> and CODE_<host>;
# no CODE_<host> means no answer (curl prints 000 for -w and fails)
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
fmt="" quiet=""
while [ $# -gt 1 ]; do
  case "$1" in -w) fmt=$2; shift ;; -o) quiet=1; shift ;; esac
  shift
done
host=${1#http://}; host=${host%%/*}; host=${host%%:*}
body_var="BODY_$host" code_var="CODE_$host"
code=${!code_var:-000}
[ "$code" = 000 ] || [ -n "$quiet" ] || printf '%s' "${!body_var:-}"
[ -z "$fmt" ] || printf '%b' "${fmt//%\{http_code\}/$code}"
[ "$code" != 000 ] || exit 28
STUB
chmod +x "$work/bin/curl"

fails=0
# check <description> <expected value> <host> <env...>
check() {
  local desc=$1 want=$2 host=$3; shift 3
  rm -f "$work/out"
  env PATH="$work/bin:$PATH" "$@" bash "$root/test/e2e/record.sh" 2 "$work/out" "t=http://$host/system/gwinfo" >/dev/null 2>&1
  local got
  got=$(head -1 "$work/out" 2>/dev/null | sed 's/^[^ ]* t=//')
  if [ "$got" = "$want" ]; then echo "ok   $desc"; else echo "FAIL $desc (got '$got', want '$want')"; fails=$((fails + 1)); fi
}

check "no answer is down" down gwa
check "pair Master" Master/Active gwb CODE_gwb=200 BODY_gwb="ContextStatus=RUNNING;RedundancyStatus=Master;RedundantState=Good;RedundantNodeActiveStatus=Active;"
check "cold Backup" Backup/Cold gwc CODE_gwc=200 BODY_gwc="ContextStatus=RUNNING;RedundancyStatus=Backup;RedundantNodeActiveStatus=Cold;"
check "standalone with redundancy fields" Independent/Active gwd CODE_gwd=200 BODY_gwd="ContextStatus=RUNNING;RedundancyStatus=Independent;RedundantNodeActiveStatus=Active;"
check "gwinfo without redundancy fields is Independent" Independent gwe CODE_gwe=200 BODY_gwe="ContextStatus=RUNNING;"
check "ingress 503 is an error, not Independent" error:503 gwf CODE_gwf=503 BODY_gwf="no healthy upstream"
check "empty 502 is an error" error:502 gwg CODE_gwg=502

# a plain URL records the HTTP status
rm -f "$work/out"
env PATH="$work/bin:$PATH" CODE_web=200 bash "$root/test/e2e/record.sh" 2 "$work/out" "p=http://web/StatusPing" >/dev/null 2>&1
got=$(head -1 "$work/out" | sed 's/^[^ ]* p=//')
if [ "$got" = 200 ]; then echo "ok   plain URL records the status"; else echo "FAIL plain URL records the status (got '$got')"; fails=$((fails + 1)); fi

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
