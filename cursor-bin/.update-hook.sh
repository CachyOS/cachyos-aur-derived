#!/usr/bin/env bash
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
info="$(curl -fsSL https://api2.cursor.sh/updates/api/download/stable/linux-x64/cursor)"
version="$(jq -r .version <<<"$info")"
commit="$(jq -r .commitSha <<<"$info")"
[[ "$version" == "$pkgver" && "$commit" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'error: cursor API reports %s (%s), expected %s\n' "$version" "$commit" "$pkgver" >&2
  exit 1
}

sed -i "s/^_commit=.*/_commit=${commit}/" PKGBUILD
