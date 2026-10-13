#!/usr/bin/env bash
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
tag="$(gh api 'repos/uazo/cromite/releases?per_page=30' \
  --jq ".[] | select(.tag_name | startswith(\"v${pkgver}-\")) | .tag_name" | head -n1)"
commit="${tag#"v${pkgver}-"}"
[[ -n "$tag" && "$commit" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'error: no cromite release found for %s\n' "$pkgver" >&2
  exit 1
}

sed -i "s/^_cromite_commit=.*/_cromite_commit='${commit}'/" PKGBUILD
