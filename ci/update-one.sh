#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
  printf 'usage: %s <package-dir>\n' "$0" >&2
  exit 2
fi

pkg="$1"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ ! -f "$pkg/PKGBUILD" ]]; then
  printf 'error: %s/PKGBUILD does not exist\n' "$pkg" >&2
  exit 1
fi

# .update-hook.sh updates values that pkgctl cannot derive from pkgver
# (commit hashes, bundled dependency versions) before checksums are computed.
if [[ -f "$pkg/.update-hook.sh" ]]; then
  pkgctl version upgrade --no-update-checksums "$pkg"
  (
    cd "$pkg"
    bash ./.update-hook.sh
    updpkgsums
  )
else
  pkgctl version upgrade "$pkg"
fi

(
  cd "$pkg"
  makepkg --printsrcinfo >.SRCINFO
  if [[ "${VERIFY_SOURCE:-false}" == "true" ]]; then
    makepkg --verifysource --noconfirm
  fi
)
