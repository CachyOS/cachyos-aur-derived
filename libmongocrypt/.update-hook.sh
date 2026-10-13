#!/usr/bin/env bash
set -euo pipefail

pkgver="$(sed -n 's/^pkgver=//p' PKGBUILD)"
mongocver="$(curl -fsSL "https://raw.githubusercontent.com/mongodb/libmongocrypt/${pkgver}/cmake/FetchMongoC.cmake" \
  | sed -n 's/^set (MONGOC_FETCH_TAG_FOR_LIBBSON "\([^"]*\)".*/\1/p')"
[[ -n "$mongocver" ]] || {
  printf 'error: unable to determine mongo-c-driver version for libmongocrypt %s\n' "$pkgver" >&2
  exit 1
}

sed -i "s/^_mongocver=.*/_mongocver='${mongocver}'/" PKGBUILD
