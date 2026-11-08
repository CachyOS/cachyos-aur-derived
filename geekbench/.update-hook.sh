#!/usr/bin/env bash
set -euo pipefail

# The main binary is named after the major version (geekbench6, geekbench7, ...).
# Geekbench 7 also renamed the data files from .plar to .plxr.
pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
sed -i -e "s/\${pkgname}[0-9]\+/\${pkgname}${pkgver%%.*}/g" -e 's/\.plar/.plxr/g' PKGBUILD
