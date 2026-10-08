#!/usr/bin/env bash
# Runs the e2e staging-watch guardrail (test/e2e/lib.sh) against a stub curl
# that plays back scripted results, and checks when it aborts a run.
# Usage: test/scripts/watch_test.sh   (about 30 seconds)
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
# curl: each call to http://<host>/ prints the next code from $SEQ_DIR/<host>
# (one code per line; the last code repeats); 000 means no answer. Like curl,
# it prints the code only for -w
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
w=""
for a in "$@"; do [ "$a" = -w ] && w=1; url=$a; done
host=${url#http://}; host=${host%%/*}
f="$SEQ_DIR/$host"; n=$(cat "$f.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$f.n"
code=$(sed -n "${n}p" "$f"); [ -n "$code" ] || code=$(tail -1 "$f")
[ -z "$w" ] || printf '%s' "$code"
[ "$code" != 000 ] || exit 7
STUB
chmod +x "$work/bin/curl"

fails=0
# check <description> <want: abort|continue> <seconds> <watched codes> [control codes]
check() {
  local desc=$1 want=$2 secs=$3 watched=$4 control=${5:-} dir="$work/$RANDOM"
  mkdir -p "$dir/seq" "$dir/out"
  tr ' ' '\n' <<< "$watched" > "$dir/seq/dash"
  [ -z "$control" ] || tr ' ' '\n' <<< "$control" > "$dir/seq/ctl"
  (
    export PATH="$work/bin:$PATH" SEQ_DIR="$dir/seq" E2E_OUT="$dir/out"
    [ -z "$control" ] || export E2E_WATCH_CONTROL="http://ctl/"
    source "$root/test/e2e/lib.sh"
    set +e
    e2e_watch_start "http://dash/" 2>/dev/null
    log "step under test" 2>/dev/null
    sleep "$secs"
    e2e_watch_stop 2>/dev/null
  )
  local got=continue
  [ ! -s "$dir/out/watch.abort" ] || got=abort
  if [ "$got" = "$want" ]; then echo "ok   $desc"; else echo "FAIL $desc (got $got, want $want)"; cat "$dir/out/watch.log"; fails=$((fails + 1)); fi
  if [ "$desc" = "logs the step and the control result" ]; then
    grep -q "not counted, control also failed.*during: step under test" "$dir/out/watch.log" ||
      { echo "FAIL watch.log lacks the control result or step"; cat "$dir/out/watch.log"; fails=$((fails + 1)); }
  fi
}

check "a healthy URL does not abort" continue 4 "200"
check "one failure does not abort" continue 6 "200 000 200"
check "two failures in a row do not abort" continue 7 "200 000 000 200"
check "three failures in a row abort" abort 7 "200 000 000 000 200"
check "failures broken up by successes do not abort" continue 9 "000 000 200 000 000 200"
check "failures while the control also fails are not counted" continue 7 "000 000 000 000 200" "000"
check "logs the step and the control result" continue 5 "200 000 200" "000"
check "failures with a healthy control abort" abort 7 "000 000 000 200" "200"

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
