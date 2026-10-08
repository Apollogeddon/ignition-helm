#!/bin/bash
# Packages every chart into .cr-release-packages, with each package's release notes
# beside it (<chart>-<version>.md): the newest section of the chart's CHANGELOG.md,
# or the chart's description when there is none.
set -euo pipefail

rm -rf .cr-release-packages
mkdir -p .cr-release-packages

for dir in charts/*/; do
  dir="${dir%/}"
  [ -f "$dir/Chart.yaml" ] || continue
  pkg=$(helm package "$dir" --destination .cr-release-packages | sed 's/^.*: //')
  notes="${pkg%.tgz}.md"
  if [ -f "$dir/CHANGELOG.md" ]; then
    awk '/^## /{n++} n==1' "$dir/CHANGELOG.md" >"$notes"
  fi
  if [ ! -s "$notes" ]; then
    sed -n 's/^description: //p' "$dir/Chart.yaml" >"$notes"
  fi
  echo "Packaged $pkg"
done
