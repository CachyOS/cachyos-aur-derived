#!/usr/bin/env bash
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
short_ver="$(sed -n 's/^_short_ver=//p' PKGBUILD)"
runtimever="${pkgver%.sdk*}"
sdkver="${short_ver}.${pkgver##*.sdk}"
[[ "$runtimever" == "$short_ver".* && "$sdkver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'error: cannot derive runtime and SDK versions from %s\n' "$pkgver" >&2
  exit 1
}

sed -i -e "s/^_runtimever=.*/_runtimever=${runtimever}/" -e "s/^_sdkver=.*/_sdkver=${sdkver}/" PKGBUILD
