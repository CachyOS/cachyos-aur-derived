#!/usr/bin/env bash
set -euo pipefail

commit="$(git ls-remote https://invent.kde.org/utilities/kwi.git HEAD | cut -f1)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'error: unable to resolve kwi commit: %s\n' "$commit" >&2
  exit 1
}

sed -i "s/^_commit=.*/_commit=${commit}/" PKGBUILD
