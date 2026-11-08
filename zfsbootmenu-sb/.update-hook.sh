#!/usr/bin/env bash
set -euo pipefail

commit="$(git ls-remote https://github.com/KorewaKiyo/zfsbootmenu-sb.git HEAD | cut -f1)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'error: unable to resolve zfsbootmenu-sb commit\n' >&2
  exit 1
}

sed -i "s|zfsbootmenu-sb.git#commit=[0-9a-f]*|zfsbootmenu-sb.git#commit=${commit}|" PKGBUILD
