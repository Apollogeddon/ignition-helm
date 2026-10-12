#!/usr/bin/env bash
# ok() evals each check later, so its single-quoted expressions are deliberate
# shellcheck disable=SC2016
# Runs the release job's require-common.sh in a copy of the charts, against a local
# origin and a gh that records what it was asked.
# Usage: test/scripts/require-common_test.sh
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
export HELM="${HELM:-helm}"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

git init --quiet --bare "$work/origin.git"
git init --quiet -b main "$work/repo"
cp -r "$root/charts" "$work/repo/"
rm -rf "$work/repo"/charts/*/charts
mkdir "$work/bin"
printf '%s\n' '#!/bin/sh' 'echo "$@" >> "$GH_LOG"' > "$work/bin/gh"
chmod +x "$work/bin/gh"
export GH_LOG="$work/gh.log"; : > "$work/gh.log"; export GITHUB_REPOSITORY=Apollogeddon/ignition-helm PATH="$work/bin:$PATH"
cd "$work/repo" || exit 1
git config user.name t && git config user.email t@t && git config core.hooksPath /dev/null
git add -A && git commit --quiet -m init
git remote add origin "$work/origin.git" && git push --quiet origin main

fails=0
run() { git switch --quiet main 2>/dev/null; bash "$root/.github/scripts/ci/require-common.sh" > "$work/out" 2>&1; echo $? > "$work/rc"; }
rc() { cat "$work/rc"; }
range() { sed -n '/- name: ignition-common/{n;s/^ *version: *//p;}' "$1" | tr -d '"'; }
on() { git show "origin/$1:charts/$2/Chart.yaml" > "$work/c.yaml" 2>/dev/null && range "$work/c.yaml"; }
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; sed 's/^/     /' "$work/out"; fails=$((fails + 1)); fi; }

common=$(sed -n 's/^version: *//p' charts/common/Chart.yaml | tr -d '"')
run
ok "charts that already require common's version are left alone" '[ "$(rc)" = 0 ] && [ ! -s "$GH_LOG" ] && grep -q "every chart requires" "$work/out"'

# a release takes common to a new version
sed -i 's/^version: .*/version: 9.9.9/' charts/common/Chart.yaml
git commit --quiet -am "chore: release common 9.9.9" && git push --quiet origin main
run; git fetch --quiet origin
ok "a pull request branch raises every chart that bundles common" '[ "$(rc)" = 0 ] && [ "$(on chore/ignition-common-9.9.9 failover)" = "^9.9.9" ] && [ "$(on chore/ignition-common-9.9.9 scaleout)" = "^9.9.9" ]'
ok "its Chart.lock files name the new version" 'git show origin/chore/ignition-common-9.9.9:charts/failover/Chart.lock | grep -q "version: 9.9.9"'
ok "the commit is a fix, so release-please releases the charts" '[ "$(git log -1 --format=%s origin/chore/ignition-common-9.9.9)" = "fix: require ignition-common ^9.9.9 in the charts that bundle it" ]'
ok "the commit touches only the charts that bundle common" 'git rev-parse -q --verify origin/chore/ignition-common-9.9.9 >/dev/null && [ -z "$(git diff --name-only origin/main origin/chore/ignition-common-9.9.9 | grep -v -e "^charts/failover/Chart\." -e "^charts/scaleout/Chart\.")" ]'
ok "it opens a pull request against main" 'grep -q "^pr create --repo Apollogeddon/ignition-helm --base main --head chore/ignition-common-9.9.9" "$GH_LOG"'

: > "$GH_LOG"; run
ok "a run while the pull request is open opens no other" '[ "$(rc)" = 0 ] && [ ! -s "$GH_LOG" ] && grep -q "already open" "$work/out"'

# a common release left in place where the job had rewritten a Chart.lock
echo "# rewritten" >> charts/failover/Chart.lock
sed -i 's/^version: .*/version: 9.9.10/' charts/common/Chart.yaml
git commit --quiet -m "chore: release common 9.9.10" -- charts/common/Chart.yaml && git push --quiet origin main
echo "# rewritten" >> charts/failover/Chart.lock
run; git fetch --quiet origin
ok "local changes from earlier steps don't stop it" '[ "$(rc)" = 0 ] && [ "$(on chore/ignition-common-9.9.10 failover)" = "^9.9.10" ]'
ok "and don't end up in its commit" '! git show origin/chore/ignition-common-9.9.10:charts/failover/Chart.lock | grep -q rewritten'

echo "common was $common"
if [ "$fails" -ne 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
