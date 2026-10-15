#!/usr/bin/env bash
# ok() evals each check later, so its single-quoted expressions are deliberate
# shellcheck disable=SC2016
# Runs the chart's seed-data-volume.sh against temporary image and data directories.
# Usage: test/scripts/seed-data-volume_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

"$HELM" template t "$root/charts/failover" --show-only templates/configmap-scripts.yaml |
  awk '/^  seed-data-volume.sh: \|-/ {on=1; next} on && /^  [^ ]/ {on=0} on {sub(/^    /, ""); print}' > "$work/seed.sh"
[ -s "$work/seed.sh" ] || { echo "could not extract seed-data-volume.sh"; exit 1; }

# the image's data directory: a file, a nested file, a symlink and a dotfile
mkdir -p "$work/image/db"
echo hidden > "$work/image/.hidden"
echo config > "$work/image/gateway.xml"
echo state > "$work/image/db/config.idb"
ln -s gateway.xml "$work/image/link.xml"

fails=0
fresh() { rm -rf "$work/data"; mkdir "$work/data"; }
run() { DATA_DIR="$work/data" SEED_DIR="$work/image" bash "$work/seed.sh" > "$work/out" 2>&1; echo $? > "$work/rc"; }
# a cp that copies one file and then fails, as a copy that runs out of space would
mkdir "$work/bin"
printf '%s\n' '#!/bin/sh' "$(command -v cp)"' -p "$SEED_DIR/gateway.xml" "$DATA_DIR/"' 'echo "cp: No space left on device" >&2' 'exit 1' > "$work/bin/cp"
chmod +x "$work/bin/cp"
failing() { PATH="$work/bin:$PATH" run; }
# a cp that refuses to copy onto the data directory itself, as a volume's root whose times
# the gateway user may not set; it copies whatever else it is given
mkdir "$work/rootbin"
printf '%s\n' '#!/bin/sh' 'for a in "$@"; do case "$a" in */.) echo "cp: preserving times for $a: Operation not permitted" >&2; exit 1 ;; esac; done' "exec $(command -v cp) \"\$@\"" > "$work/rootbin/cp"
chmod +x "$work/rootbin/cp"
volume_root() { PATH="$work/rootbin:$PATH" run; }
rc() { cat "$work/rc"; }
seeded() { cmp -s "$work/image/gateway.xml" "$work/data/gateway.xml" && cmp -s "$work/image/db/config.idb" "$work/data/db/config.idb" && [ -L "$work/data/link.xml" ] && cmp -s "$work/image/.hidden" "$work/data/.hidden"; }
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; sed 's/^/     /' "$work/out"; fails=$((fails + 1)); fi; }

fresh; run
ok "first start copies the image's data" 'seeded'
ok "first start writes the marker" '[ "$(rc)" = 0 ] && [ -f "$work/data/.ignition-seed-complete" ]'

echo changed > "$work/data/gateway.xml"; run
ok "a seeded volume is not copied again" '[ "$(cat "$work/data/gateway.xml")" = changed ] && ! grep -q Seeding "$work/out"'

fresh; failing
ok "a failed copy fails the script" '[ "$(rc)" != 0 ]'
ok "a failed copy leaves no marker" '[ ! -f "$work/data/.ignition-seed-complete" ]'
ok "a failed copy leaves the volume half-filled" '[ -f "$work/data/gateway.xml" ] && [ ! -e "$work/data/db" ]'
run
ok "the next start redoes the copy" '[ "$(rc)" = 0 ] && seeded && [ -f "$work/data/.ignition-seed-complete" ]'

fresh; volume_root
ok "the copy leaves the volume root's own times alone" '[ "$(rc)" = 0 ] && seeded'

# a copy killed partway: some files there, no marker
fresh; echo partial > "$work/data/gateway.xml"; run
ok "an interrupted copy is redone over the partial files" 'seeded && [ -f "$work/data/.ignition-seed-complete" ]'

if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
