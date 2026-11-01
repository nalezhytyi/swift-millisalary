#!/usr/bin/env bash
# Builds the dmg and publishes it as a GitHub release for MARKETING_VERSION
# in project.yml:  scripts/release.sh
#
# This pushes nothing by itself, but `gh release create` publishes: it makes
# the tag on GitHub and uploads the dmg, so run it only when you mean to
# ship. Needs `gh` signed in as the account that owns the repository
# (MillisalaryReleasesRepo in project.yml, which the update check reads too).
set -euo pipefail

cd "$(dirname "$0")/.."

version="$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1 | tr -d '"')"
repo="$(sed -n 's/^ *MillisalaryReleasesRepo: *//p' project.yml | head -1)"
tag="v${version}"

if [ -z "$version" ] || [ -z "$repo" ]; then
  echo "MARKETING_VERSION or MillisalaryReleasesRepo missing from project.yml." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree isn't clean; commit or stash first." >&2
  exit 1
fi
if ! origin="$(git remote get-url origin 2>/dev/null)"; then
  echo "No 'origin' remote: create the GitHub repository ${repo} and push first." >&2
  exit 1
fi
# The whole URL, over HTTPS or SSH: a pattern with wildcards would also let
# swift-millisalary-old or notgithub.com through
case "$origin" in
  "https://github.com/${repo}" | "https://github.com/${repo}.git" | \
  "git@github.com:${repo}" | "git@github.com:${repo}.git" | \
  "ssh://git@github.com/${repo}" | "ssh://git@github.com/${repo}.git") ;;
  *) echo "'origin' is ${origin}, not ${repo}." >&2; exit 1 ;;
esac
# More than one GitHub account may be signed in (gh auth status)
owner="${repo%%/*}"
account="$(gh api user --jq .login)"
if [ "$account" != "$owner" ]; then
  echo "gh is using ${account}, not ${owner}: run it as GH_TOKEN=\"\$(gh auth token --user ${owner})\" scripts/release.sh" >&2
  exit 1
fi
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  echo "Release ${tag} already exists; bump MARKETING_VERSION in project.yml." >&2
  exit 1
fi
# The tag goes on the commit the dmg is built from, so GitHub must have it
git fetch --quiet origin
commit="$(git rev-parse HEAD)"
if ! git merge-base --is-ancestor "$commit" "@{upstream}" 2>/dev/null; then
  echo "HEAD isn't pushed (or the branch has no upstream); push it first." >&2
  exit 1
fi

dmg="$(scripts/build-dmg.sh | tail -1)"

gh release create "$tag" "$dmg" \
  --repo "$repo" \
  --target "$commit" \
  --title "Millisalary ${version}" \
  --generate-notes
