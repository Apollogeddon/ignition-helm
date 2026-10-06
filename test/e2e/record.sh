#!/usr/bin/env bash
# record.sh <seconds> <outfile> <name=url>...: once a second, record each URL's
# HTTP status and, for /system/gwinfo URLs, the redundancy role/state that answered
set -uo pipefail
end=$(( $(date +%s) + $1 )); out=$2; shift 2
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
while [ "$(date +%s)" -lt "$end" ]; do
  t=$(date -u +%H:%M:%S); i=0
  for target in "$@"; do
    i=$((i + 1)); name=${target%%=*}; url=${target#*=}
    case "$url" in
      */system/gwinfo) ( b=$(curl -sk --max-time 1.5 "$url"); [ -n "$b" ] || b="down"
           echo "$name=$(tr ';' '\n' <<< "$b" | grep -E '^(RedundancyStatus|RedundantNodeActiveStatus)=' | sed 's/^[^=]*=//' | paste -sd/ -)" > "$tmp/$i" ) & ;;
      *) ( echo "$name=$(curl -sk --max-time 1.5 -o /dev/null -w '%{http_code}' "$url")" > "$tmp/$i" ) & ;;
    esac
  done
  wait; echo "$t $(cat "$tmp"/* | paste -sd' ' -)" >> "$out"; rm -f "$tmp"/*
  sleep 1
done
