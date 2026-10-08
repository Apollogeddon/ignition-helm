#!/bin/bash
# Creates a tag and GitHub release, with the chart attached, for each packaged chart
# version that has no release yet, and copies those packages to .cr-new-packages for
# the chart index. gh creates each release as a draft, attaches the chart and then
# publishes it, as a published release may be immutable and refuse new files.
set -euo pipefail

rm -rf .cr-new-packages
mkdir -p .cr-new-packages

released=false
for pkg in .cr-release-packages/*.tgz; do
  tag=$(basename "$pkg" .tgz)
  if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    echo "$tag is already released"
    continue
  fi
  gh release create "$tag" "$pkg" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
    --title "$tag" --notes-file "${pkg%.tgz}.md"
  cp "$pkg" .cr-new-packages/
  released=true
done

echo "released=$released" >>"${GITHUB_OUTPUT:-/dev/null}"
