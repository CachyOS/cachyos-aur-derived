#!/usr/bin/env bash
# Keep this URL identical to cursor-bin/.nvchecker.toml.
set -euo pipefail

dev_url="https://api2.cursor.sh/updates/api/update/linux-x64/cursor/0.0.0/deadbeef/dev"

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
info="$(curl -fsSL -A 'cachyos-cursor-bin-update/1.0' "$dev_url")"
version="$(jq -r .version <<<"$info")"
download_url="$(jq -r .url <<<"$info")"
commit="$(sed -n 's|.*/production/\([0-9a-f]\{40\}\)/.*|\1|p' <<<"$download_url")"
[[ "$version" == "$pkgver" && "$commit" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'error: cursor nightly API reports %s (%s), expected %s\n' "$version" "$commit" "$pkgver" >&2
  exit 1
}

sed -i "s/^_commit=.*/_commit=${commit}/" PKGBUILD

deb="cursor_${pkgver}_amd64.deb"
if [[ ! -f "$deb" ]]; then
  curl -fL --retry 3 --retry-delay 2 -o "${deb}.partial" \
    "https://downloads.cursor.com/production/${commit}/linux/x64/deb/amd64/deb/${deb}"
  mv "${deb}.partial" "$deb"
fi

mapfile -t electron_majors < <(
  bsdtar -xOf "$deb" data.tar.xz |
    tar -xJOf - ./usr/share/cursor/cursor |
    grep -a -o 'Electron/[0-9][0-9]*' |
    sort -u
)
if ((${#electron_majors[@]} != 1)); then
  printf 'error: expected one Electron major in %s, got: %s\n' \
    "$deb" "${electron_majors[*]:-none}" >&2
  exit 1
fi
major="${electron_majors[0]#Electron/}"
sed -i "s/^_electron=.*/_electron=electron${major}/" PKGBUILD
