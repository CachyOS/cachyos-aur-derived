#!/usr/bin/env bash
# Copy variables that pkgctl cannot derive from pkgver (commit hashes, release
# ids) from the AUR PKGBUILD of the same version. Run from a package directory,
# normally through its .update-hook.sh: sync-from-aur.sh <variable>...
set -euo pipefail

if (($# == 0)); then
  printf 'usage: %s <variable>...\n' "$0" >&2
  exit 2
fi

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

pkg="$(basename "$PWD")"
pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
aur="$(mktemp -d)"
trap 'rm -rf "$aur"' EXIT

git clone -q --depth 1 "https://aur.archlinux.org/${pkg}.git" "$aur"
aur_pkgver="$(sed -n 's/^[[:space:]]*pkgver = //p' "$aur/.SRCINFO")"
[[ "$aur_pkgver" == "$pkgver" ]] || die "AUR has ${pkg} ${aur_pkgver}, expected ${pkgver}"

# The value ends up in a PKGBUILD, so only allow plain values and $references.
safe_line="^[A-Za-z0-9_]+=['\"]?[A-Za-z0-9_.:+\$-]*['\"]?\$"
for var in "$@"; do
  grep -q "^${var}=" PKGBUILD || die "${var} is not set in the local PKGBUILD"
  line="$(grep -m1 "^${var}=" "$aur/PKGBUILD")" || die "${var} is not set in the AUR PKGBUILD"
  [[ "$line" =~ $safe_line ]] || die "unexpected AUR value: ${line}"
  sed -i "s|^${var}=.*|${line}|" PKGBUILD
done
