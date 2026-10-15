#!/usr/bin/env bash
# ok() evals each check later, so its single-quoted expressions are deliberate
# shellcheck disable=SC2016,SC2034
# Runs the chart's prepare-gan-certificates.sh against a stub keytool and a
# temporary data directory. Usage: test/scripts/prepare-gan-certificates_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" --show-only templates/configmap-scripts.yaml |
  awk '/^  prepare-gan-certificates.sh: \|-/ {on=1; next} on && /^  [^ ]/ {on=0} on {sub(/^    /, ""); print}' > "$work/gan.sh"
[ -s "$work/gan.sh" ] || { echo "could not extract prepare-gan-certificates.sh"; exit 1; }

mkdir "$work/bin" "$work/ca" "$work/tls"
# ca.crt is the issuer's root, tls.crt the release's own GAN CA
echo issuer-root > "$work/ca/ca.crt"; echo release-ca > "$work/ca/tls.crt"; echo keystore > "$work/tls/keystore.p12"
# keytool stub: fails unless -storepass is exactly $WANT; -changealias calls are recorded in $CALLS
cat > "$work/bin/keytool" <<'STUB'
#!/usr/bin/env bash
pass=; prev=
for arg in "$@"; do [ "$prev" = -storepass ] && pass=$arg; prev=$arg; done
[ "$pass" = "$WANT" ] || { echo "keytool: wrong storepass" >&2; exit 1; }
case "$1" in
  -list) echo "gan-client, Oct 12, 2026, PrivateKeyEntry," ;;
  -changealias) echo "$*" >> "$CALLS" ;;
esac
STUB
chmod +x "$work/bin/keytool"

fails=0
# run <passphrase>: run the script once with that keystore passphrase; sets $rc
run() {
  rm -rf "$work/data"; mkdir "$work/data"; : > "$work/calls"
  env PATH="$work/bin:$PATH" CALLS="$work/calls" WANT="$1" METRO_KEYSTORE_PASSPHRASE="$1" \
    bash "$work/gan.sh" -c "$work/ca" -s "$work/tls" -d "$work/data" > "$work/out" 2>&1
  rc=$?
}
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; sed 's/^/     /' "$work/out"; fails=$((fails + 1)); fi; }

run secret
ok "the keystore is renamed to metro-key" '[ $rc = 0 ] && grep -q -- "-destalias metro-key" "$work/calls"'
trusted="$work/data/gateway-network/%s/security/pki/trusted/certs/ignition-gan-ca.crt"
# shellcheck disable=SC2059
ok "the release's CA is trusted for the gateway network, not the issuer's root" \
  '[ "$(cat "$(printf "$trusted" server)")" = release-ca ] && [ "$(cat "$(printf "$trusted" client)")" = release-ca ]'

run 'two words *'
ok "a passphrase with spaces and globs reaches keytool whole" '[ $rc = 0 ] && grep -q -- "-destalias metro-key" "$work/calls"'

rm "$work/ca/tls.crt"; run secret
ok "a CA secret without tls.crt fails the init container" '[ $rc -ne 0 ] && grep -q "tls.crt" "$work/out"'

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
