#!/usr/bin/env bash
set -euo pipefail

commit="$(git ls-remote https://gitlab.com/AirVPN/AirVPN-Suite.git HEAD | cut -f1)"
openvpn3_commit="$(git ls-remote https://github.com/AirVPN/openvpn3-airvpn.git HEAD | cut -f1)"
asio_ver="$(curl -fsSL "https://raw.githubusercontent.com/AirVPN/openvpn3-airvpn/${openvpn3_commit}/deps/vcpkg-ports/asio/vcpkg.json" \
  | jq -r .version | tr . -)"
[[ "$commit" =~ ^[0-9a-f]{40}$ && "$openvpn3_commit" =~ ^[0-9a-f]{40}$ && "$asio_ver" =~ ^[0-9]+(-[0-9]+)+$ ]] || {
  printf 'error: unable to resolve hummingbird sources: %s %s %s\n' "$commit" "$openvpn3_commit" "$asio_ver" >&2
  exit 1
}

sed -i -e "s/^_commit=.*/_commit=${commit}/" \
  -e "s/^_openvpn3_commit=.*/_openvpn3_commit=${openvpn3_commit}/" \
  -e "s/^_asio_ver=.*/_asio_ver=${asio_ver}/" PKGBUILD
