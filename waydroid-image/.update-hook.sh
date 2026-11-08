#!/usr/bin/env bash
set -euo pipefail

bash ../ci/sync-from-aur.sh _pkgver_sys _pkgver_vendor _pkgver_images_vendor
