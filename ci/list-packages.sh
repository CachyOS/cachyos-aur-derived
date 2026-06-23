#!/usr/bin/env bash
set -euo pipefail

find . -mindepth 2 -maxdepth 2 -name PKGBUILD -printf '%h\n' \
  | sed 's#^\./##' \
  | sort
