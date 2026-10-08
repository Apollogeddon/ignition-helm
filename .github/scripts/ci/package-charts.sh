#!/bin/bash
# Packages every chart into .cr-release-packages for chart-releaser, which then
# releases only the versions that have no release yet. Each package carries the
# newest section of the chart's CHANGELOG.md as RELEASE-NOTES.md, which
# chart-releaser uses as the release description.
set -euo pipefail

rm -rf .cr-release-packages
mkdir -p .cr-release-packages

for dir in charts/*/; do
  dir="${dir%/}"
  [ -f "$dir/Chart.yaml" ] || continue
  if [ -f "$dir/CHANGELOG.md" ]; then
    awk '/^## /{n++} n==1' "$dir/CHANGELOG.md" >"$dir/RELEASE-NOTES.md"
  fi
  helm package "$dir" --destination .cr-release-packages
  rm -f "$dir/RELEASE-NOTES.md"
done
