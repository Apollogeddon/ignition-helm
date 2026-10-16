#!/bin/bash
# Opens a pull request raising each chart that bundles ignition-common to require the
# version it's now at. A chart packages common when it's released itself, and
# release-please only releases a chart whose own files changed, so without this a
# common release never reaches the charts' users. The pull request's fix commit touches
# each chart, so merging it releases them with the new common.
set -euo pipefail

common=$(sed -n 's/^version: *//p' charts/common/Chart.yaml | tr -d '"')
want="^$common"

# the range each chart gives on the line after its ignition-common dependency
range() { sed -n '/- name: ignition-common/{n;s/^ *version: *//p;}' "$1" | tr -d '"'; }

stale=()
for chart in charts/*/Chart.yaml; do
  have=$(range "$chart")
  if [ -n "$have" ] && [ "$have" != "$want" ]; then
    stale+=("$(dirname "$chart")")
  fi
done
if [ "${#stale[@]}" -eq 0 ]; then
  echo "every chart requires ignition-common $want"
  exit 0
fi

branch="chore/ignition-common-$common"
if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "$branch is already open"
  exit 0
fi

# the release job's earlier steps rewrote the Chart.lock files in place. The pull request
# leaves them alone: the release job commits fresh ones, which would conflict with its own,
# and every job that uses a chart runs helm dependency update first
git switch --quiet --discard-changes -c "$branch"
for dir in "${stale[@]}"; do
  sed -i "/- name: ignition-common/{n;s/version: .*/version: \"$want\"/;}" "$dir/Chart.yaml"
  git add "$dir/Chart.yaml"
done
title="fix: require ignition-common $want in the charts that bundle it"
git commit --quiet -m "$title"
git push --quiet origin "$branch"
gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" --title "$title" \
  --body "ignition-common $common is released. Each chart packages common when it's released itself, so this raises them to require it: merging releases ${stale[*]} with it."
