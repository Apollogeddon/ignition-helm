#!/bin/bash
# Creates a tag and GitHub release named <chart>-v<version>, with the chart and its
# cosign signature bundle attached, for each packaged chart version that has no
# release yet, and copies the packages that index.yaml doesn't list yet to
# .cr-new-packages for the chart index. Each chart is signed keyless, as this workflow,
# before its release exists: gh creates the release as a draft, attaches both files
# and then publishes it, as a published release is immutable and refuses new files.
set -euo pipefail

rm -rf .cr-new-packages
mkdir -p .cr-new-packages

released=false
for pkg in .cr-release-packages/*.tgz; do
  chart=$(helm show chart "$pkg")
  name=$(sed -n 's/^name: //p' <<<"$chart")
  version=$(sed -n 's/^version: //p' <<<"$chart")
  tag="$name-v$version"
  if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    echo "$tag is already released"
    continue
  fi
  bundle="$pkg.sigstore.json"
  cosign sign-blob --yes --bundle "$bundle" "$pkg"
  # much the check a user runs, so a bundle that wouldn't verify is never released
  cosign verify-blob "$pkg" --bundle "$bundle" \
    --certificate-identity-regexp "^https://github\.com/$GITHUB_REPOSITORY/\.github/workflows/version\.yml@" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  gh release create "$tag" "$pkg" "$bundle" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
    --title "$tag" --notes-file "${pkg%.tgz}.md"
  # versions released before the tags had a v keep their index entry and download
  if grep -qF "/$(basename "$pkg")" index.yaml; then
    echo "$name $version is already in index.yaml"
  else
    cp "$pkg" .cr-new-packages/
    released=true
  fi
done

echo "released=$released" >>"${GITHUB_OUTPUT:-/dev/null}"
