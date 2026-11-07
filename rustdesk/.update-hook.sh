#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Recipe contributors
# SPDX-License-Identifier: 0BSD
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
[[ "$pkgver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
commit="$(gh api "repos/rustdesk/rustdesk/commits/$pkgver" --jq .sha)"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
source_url="https://raw.githubusercontent.com/rustdesk/rustdesk/$commit"
bridge="$(curl -fsSL "$source_url/.github/workflows/bridge.yml")"
app="$(curl -fsSL "$source_url/.github/workflows/flutter-build.yml")"
manifest="$(curl -fsSL "$source_url/vcpkg.json")"
codegen="$(sed -n 's/^  FLUTTER_RUST_BRIDGE_VERSION: "\([0-9.]*\)".*/\1/p' <<<"$bridge")"
flutter_bridge="$(awk '
  /flutter-version:/ { sdk=$2; gsub(/[",]/, "", sdk) }
  /artifact-name:[[:space:]]*"bridge-artifact"[[:space:]]*,/ { print sdk }
' <<<"$bridge")"
flutter_app="$(sed -n 's/^  FLUTTER_VERSION: "\([0-9.]*\)".*/\1/p' <<<"$app")"
ffmpeg="$(curl -fsSL "$source_url/res/vcpkg/ffmpeg/vcpkg.json" | jq -er .version)"
nvcodec="$(jq -er '.overrides[] | select(.name == "ffnvcodec") | .version' <<<"$manifest")"
amf="$(jq -er '.overrides[] | select(.name == "amd-amf") | .version' <<<"$manifest")"
hbb="$(gh api "repos/rustdesk/rustdesk/contents/libs/hbb_common?ref=$commit" \
  --jq 'select(.submodule_git_url == "https://github.com/rustdesk/hbb_common") | .sha')"
for version in "$codegen" "$flutter_bridge" "$flutter_app" "$ffmpeg" "$nvcodec" "$amf"; do
  [[ "$version" =~ ^[0-9]+(\.[0-9]+){2,3}$ ]] || {
    printf 'error: missing or ambiguous RustDesk compatibility version\n' >&2
    exit 1
  }
done
[[ "$codegen" == 1.* && "$hbb" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'error: bridge major version or hbb_common repository needs review\n' >&2
  exit 1
}

# The existing updater stages one package only. Never edit sibling recipes;
# refuse an update until its exact build dependencies have matching recipes.
for dependency in "flutter-rust-bridge-codegen1=$codegen" "ffmpeg-rustdesk=$ffmpeg"; do
  package=${dependency%%=*}
  [[ "$(sed -n 's/^pkgver=//p' "../$package/PKGBUILD")" == "${dependency#*=}" ]] || {
    printf 'error: update %s before RustDesk %s\n' "$dependency" "$pkgver" >&2
    exit 1
  }
done
for pin in "_nvcodec=$nvcodec" "_amf=$amf"; do
  grep -qxF "$pin" ../ffmpeg-rustdesk/PKGBUILD || {
    printf 'error: ffmpeg-rustdesk header pin %s needs updating\n' "$pin" >&2
    exit 1
  }
done
ffmpeg_commit="$(sed -n 's/^_rustdesk_commit=//p' ../ffmpeg-rustdesk/PKGBUILD)"
[[ "$ffmpeg_commit" =~ ^[0-9a-f]{40}$ ]]
if [[ "$ffmpeg_commit" != "$commit" ]]; then
  # A new RustDesk release can reuse an unchanged FFmpeg tree. Changed patches
  # at the same FFmpeg version need a reviewed helper pkgrel bump first.
  old_tree="$(gh api "repos/rustdesk/rustdesk/contents/res/vcpkg?ref=$ffmpeg_commit" \
    --jq '.[] | select(.name == "ffmpeg") | .sha')"
  new_tree="$(gh api "repos/rustdesk/rustdesk/contents/res/vcpkg?ref=$commit" \
    --jq '.[] | select(.name == "ffmpeg") | .sha')"
  [[ "$old_tree" =~ ^[0-9a-f]{40}$ && "$old_tree" == "$new_tree" ]] || {
    printf 'error: review/update ffmpeg-rustdesk patches before RustDesk %s\n' "$pkgver" >&2
    exit 1
  }
fi

# All discovery and dependency checks finish before modifying this package.
sed -i \
  -e "s/^_commit=.*/_commit=$commit/" \
  -e "s/^_hbb_commit=.*/_hbb_commit=$hbb/" \
  -e "s/^_flutter_bridge=.*/_flutter_bridge=$flutter_bridge/" \
  -e "s/^_flutter_app=.*/_flutter_app=$flutter_app/" \
  -e "s/'flutter-rust-bridge-codegen1=[0-9.]*'/'flutter-rust-bridge-codegen1=$codegen'/" \
  -e "s/'ffmpeg-rustdesk=[0-9.]*'/'ffmpeg-rustdesk=$ffmpeg'/" \
  PKGBUILD
