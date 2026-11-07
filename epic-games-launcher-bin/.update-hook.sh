#!/usr/bin/env bash
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
target="$(curl -fsSL https://content-download-egs.distro.on.epicgames.com/Builds/EGLv2/stable-target.json | jq -r .version)"
commit="${target#"${pkgver}+"}"
[[ "$target" == "${pkgver}+"* && "$commit" =~ ^g[0-9a-f]+$ ]] || {
  printf 'error: Epic stable target is %s, expected %s+g<commit>\n' "$target" "$pkgver" >&2
  exit 1
}

sed -i "s/^_commit=.*/_commit=${commit}/" PKGBUILD
