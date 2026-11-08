#!/usr/bin/env bash
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
short_commit="${pkgver##*.}"
commit="$(gh api "repos/openSUSE/imagewriter/commits/${short_commit}" --jq .sha)"
[[ "$commit" =~ ^[0-9a-f]{40}$ && "$commit" == "$short_commit"* ]] || {
  printf 'error: unable to resolve imagewriter commit %s\n' "$short_commit" >&2
  exit 1
}

sed -i "s/^_commit=.*/_commit=${commit}/" PKGBUILD
