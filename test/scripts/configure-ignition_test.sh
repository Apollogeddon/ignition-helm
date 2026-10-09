#!/usr/bin/env bash
# ok() evals each check later, so its single-quoted expressions are deliberate
# shellcheck disable=SC2016,SC2034,SC2329
# Runs the chart's configure-ignition.sh, which stages a gateway backup for
# restore, against a temporary data directory and a stub curl.
# Usage: test/scripts/configure-ignition_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" --show-only templates/configmap-scripts.yaml |
  awk '/^  configure-ignition.sh: \|-/ {on=1; next} on && /^  [^ ]/ {on=0} on {sub(/^    /, ""); print}' > "$work/configure.sh"
[ -s "$work/configure.sh" ] || { echo "could not extract configure-ignition.sh"; exit 1; }

# stub curl: writes "backup from <url>" to -o, or fails like curl -f on a URL ending in /missing
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2 ;; -*) shift ;; *) url=$1; shift ;; esac; done
echo "$url" >> "${CURL_LOG:?}"
case "$url" in */missing) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;; esac
echo "backup from $url" > "$out"
STUB
chmod +x "$work/bin/curl"

fresh() { rm -rf "$work/data"; mkdir "$work/data"; : > "$work/curl.log"; }
# run [VAR=value...]: run the script with the restore variables given
run() { env -i PATH="$work/bin:/usr/bin:/bin" DATA_DIR="$work/data" CURL_LOG="$work/curl.log" "$@" bash "$work/configure.sh" > "$work/out" 2>&1; }
backup() { cat "$work/data/restore.gwbk" 2>/dev/null; }
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; sed 's/^/     /' "$work/out"; fails=$((fails + 1)); fi; }

fresh; run
ok "no restore source stages nothing" '[ ! -e "$work/data/restore.gwbk" ]'

fresh; run IGNITION_RESTORE_URL=http://files/a.gwbk
ok "a URL is downloaded to restore.gwbk" '[ "$(backup)" = "backup from http://files/a.gwbk" ]'
run IGNITION_RESTORE_URL=http://files/a.gwbk
ok "a staged backup is not downloaded again" '[ "$(wc -l < "$work/curl.log")" -eq 1 ]'
ok "and stays for the gateway's -r" '[ "$(backup)" = "backup from http://files/a.gwbk" ]'

fresh; run IGNITION_RESTORE_URL=http://files/missing; rc=$?
ok "a failed download fails the init container" '[ "$rc" -ne 0 ]'
ok "and leaves no backup or partial file behind" '[ -z "$(ls -A "$work/data")" ]'

fresh; echo "mounted backup" > "$work/mounted.gwbk"; run IGNITION_RESTORE_PATH="$work/mounted.gwbk"
ok "a path is copied to restore.gwbk" '[ "$(backup)" = "mounted backup" ]'

fresh; run IGNITION_RESTORE_PATH="$work/nope.gwbk"; rc=$?
ok "a missing path fails the init container" '[ "$rc" -ne 0 ] && [ ! -e "$work/data/restore.gwbk" ]'

[ "$fails" -eq 0 ] && echo "all passed"
exit "$fails"
