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

pkgctl version upgrade "$pkg"

(
  cd "$pkg"
  makepkg --printsrcinfo >.SRCINFO
  if [[ "${VERIFY_SOURCE:-false}" == "true" ]]; then
    makepkg --verifysource --noconfirm
  fi
)
