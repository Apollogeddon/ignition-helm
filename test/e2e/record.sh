#!/usr/bin/env bash
# record.sh <seconds> <outfile> <name=url>...: on each wall-clock second, record each URL's
# HTTP status (extra curl args from RECORD_CURL_ARGS, e.g. --resolve) and, for /system/gwinfo URLs, the redundancy role/state that answered
set -uo pipefail
end=$(( $(date +%s) + $1 )); out=$2; shift 2
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
while [ "$(date +%s)" -lt "$end" ]; do
  t=$(date -u +%H:%M:%S); i=0
  for target in "$@"; do
    i=$((i + 1)); name=${target%%=*}; url=${target#*=}
    case "$url" in
      # no answer is "down"; a reply that is not gwinfo (e.g. the ingress
      # controller's 503 while a Service has no endpoints) is "error:<code>";
      # gwinfo without redundancy fields is "Independent"
      */system/gwinfo) ( r=$(curl -sk --max-time 0.9 ${RECORD_CURL_ARGS:-} -w '\n%{http_code}' "$url" || true)
           code=${r##*$'\n'}; b=${r%$'\n'*}
           if [ -z "$code" ] || [ "$code" = 000 ]; then s=down
           elif [[ "$b" != *ContextStatus=* ]]; then s="error:$code"
           else
             s=$(tr ';' '\n' <<< "$b" | grep -E '^(RedundancyStatus|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -)
             s=${s:-Independent}
           fi
           echo "$name=$s" > "$tmp/$i" ) & ;;
      *) ( echo "$name=$(curl -sk --max-time 0.9 ${RECORD_CURL_ARGS:-} -o /dev/null -w '%{http_code}' "$url")" > "$tmp/$i" ) & ;;
    esac
  done
  wait; echo "$t $(cat "$tmp"/* | paste -sd' ' -)" >> "$out"; rm -f "$tmp"/*
  ms=$(( $(date +%s%N) / 1000000 % 1000 )); sleep "0.$(printf %03d $(( 999 - ms )))"
done
