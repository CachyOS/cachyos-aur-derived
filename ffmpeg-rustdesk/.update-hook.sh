#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Recipe contributors
# SPDX-License-Identifier: 0BSD
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
release="$(gh api repos/rustdesk/rustdesk/releases/latest --jq .tag_name)"
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
commit="$(gh api "repos/rustdesk/rustdesk/commits/$release" --jq .sha)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
source_url="https://raw.githubusercontent.com/rustdesk/rustdesk/$commit"
required="$(curl -fsSL "$source_url/res/vcpkg/ffmpeg/vcpkg.json" | jq -er .version)"
[[ "$required" == "$pkgver" ]] || {
  printf 'error: RustDesk %s requires FFmpeg %s, not %s; do not follow unreleased pins\n' \
    "$release" "$required" "$pkgver" >&2
  exit 1
}
manifest="$(curl -fsSL "$source_url/vcpkg.json")"
nvcodec="$(jq -er '.overrides[] | select(.name == "ffnvcodec") | .version' <<<"$manifest")"
amf="$(jq -er '.overrides[] | select(.name == "amd-amf") | .version' <<<"$manifest")"
for version in "$pkgver" "$nvcodec" "$amf"; do
  [[ "$version" =~ ^[0-9]+(\.[0-9]+){2,3}$ ]] || {
    printf 'error: missing or ambiguous RustDesk codec-header version\n' >&2
    exit 1
  }
done

# Keep the reviewed Linux patch set; changed patch applicability needs review.
upstream_patches="$(curl -fsSL "$source_url/res/vcpkg/ffmpeg/portfile.cmake" \
  | sed -n '/^    PATCHES$/,/^)/{ /^    PATCHES$/d; /^)/d; s/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d; /\/0012-fix-macos-big-sur-CVBufferCopyAttachments.patch$/d; p; }')"
local_patches="$(sed -n '/^_patches=(/,/^)/{ /^_patches=(/d; /^)/d; s/^[[:space:]]*//; p; }' PKGBUILD)"
[[ -n "$upstream_patches" && "$upstream_patches" == "$local_patches" ]] || {
  printf 'error: review the changed upstream FFmpeg patch list before updating\n' >&2
  exit 1
}
sed -i \
  -e "s/^_rustdesk_commit=.*/_rustdesk_commit=$commit/" \
  -e "s/^_nvcodec=.*/_nvcodec=$nvcodec/" \
  -e "s/^_amf=.*/_amf=$amf/" \
  PKGBUILD
