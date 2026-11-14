#!/usr/bin/env bash
set -euo pipefail

# The download URL carries a build suffix (e.g. bb13) that changes
# independently of pkgver, so read it from the downloads page.
pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
build="$(curl -fsSL https://www.betterbird.eu/downloads/ |
  grep -oE "${pkgver//./\\.}-bb[0-9]+" | head -n1)"
build="${build#"${pkgver}-"}"
[[ "$build" =~ ^bb[0-9]+$ ]] || {
  printf 'error: no betterbird build suffix found for %s\n' "$pkgver" >&2
  exit 1
}

sed -i "s/^_build=.*/_build=${build}/" PKGBUILD
