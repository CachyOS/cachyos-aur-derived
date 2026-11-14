#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Recipe contributors
# SPDX-License-Identifier: 0BSD
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
release="$(gh api repos/rustdesk/rustdesk/releases/latest --jq .tag_name)"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
commit="$(gh api "repos/rustdesk/rustdesk/commits/$release" --jq .sha)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
required="$(curl -fsSL "https://raw.githubusercontent.com/rustdesk/rustdesk/$commit/.github/workflows/bridge.yml" \
  | sed -n 's/^  FLUTTER_RUST_BRIDGE_VERSION: "\([0-9.]*\)".*/\1/p')"
[[ "$pkgver" =~ ^1\.[0-9]+\.[0-9]+$ && "$required" == "$pkgver" ]] || {
  printf 'error: RustDesk %s requires generator %s, not %s; do not follow unreleased/v2 pins\n' \
    "$release" "$required" "$pkgver" >&2
  exit 1
}
