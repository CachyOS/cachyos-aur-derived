#!/usr/bin/env bash
# Open one pull request per pkgbase from .ci/rebuild-check/rebuild.json that
# bumps pkgrel so the build server rebuilds it against current libraries.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

rebuild_json=".ci/rebuild-check/rebuild.json"
failures_file=".ci/rebuild-check/pr-failures.txt"

if [[ ! -f "$rebuild_json" ]]; then
  printf 'error: run ci/check-rebuilds.sh before ci/open-rebuild-prs.sh\n' >&2
  exit 1
fi

if [[ "$(jq 'length' "$rebuild_json")" == 0 ]]; then
  printf 'No packages need a rebuild.\n'
  exit 0
fi

base_branch="${BASE_BRANCH:-${GITHUB_REF_NAME:-master}}"
rebuild_limit="${REBUILD_LIMIT:-10}"
git_author_name="${GIT_AUTHOR_NAME:-cachyos-update-bot}"
git_author_email="${GIT_AUTHOR_EMAIL:-cachyos-update-bot@users.noreply.github.com}"

export GIT_AUTHOR_NAME="$git_author_name"
export GIT_AUTHOR_EMAIL="$git_author_email"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$git_author_name}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$git_author_email}"

git config user.name "$git_author_name"
git config user.email "$git_author_email"
git config --global --add safe.directory "$repo_root"

git fetch origin "$base_branch"

mkdir -p .ci/pr-bodies
: >"$failures_file"

open_prs_json="$(gh pr list --state open --limit 500 --json number,headRefName,title)"

reset_to_base() {
  git checkout -B "$base_branch" "origin/$base_branch"
  git reset --hard "origin/$base_branch"
}

fail() {
  printf '%s: %s\n' "$1" "$2" >>"$failures_file"
  printf 'Rebuild PR failed for %s: %s\n' "$1" "$2" >&2
  reset_to_base
}

srcinfo_version() {
  awk '
    $1 == "pkgver" { ver = $3 }
    $1 == "pkgrel" && !rel { rel = $3 }
    $1 == "epoch" && !ep { ep = $3 }
    END { print (ep ? ep ":" : "") ver "-" rel }' "$1/.SRCINFO"
}

count=0
while IFS= read -r entry; do
  if ((count >= rebuild_limit)); then
    printf 'Reached REBUILD_LIMIT=%s\n' "$rebuild_limit"
    break
  fi

  pkg="$(jq -r '.pkgbase' <<<"$entry")"
  repo_version="$(jq -r '.repo_version' <<<"$entry")"
  safe_version="$(printf '%s' "$repo_version" | tr -c 'A-Za-z0-9._-' '-')"
  branch="bot/rebuild/${pkg}-${safe_version}"

  # An open version update (or an earlier rebuild PR) rebuilds the package anyway.
  existing="$(jq -r --arg pkg "$pkg" --arg branch "$branch" '
    [.[] | select(.headRefName == $branch
                  or (.title | startswith($pkg + ": update to "))
                  or (.title | startswith($pkg + ": rebuild")))
     | "#\(.number)"] | join(" ")' <<<"$open_prs_json")"
  if [[ -n "$existing" ]]; then
    printf 'Skipping %s: open PR %s already rebuilds it\n' "$pkg" "$existing"
    continue
  fi

  git checkout -B "$branch" "origin/$base_branch"
  git reset --hard "origin/$base_branch"

  if [[ ! -f "$pkg/PKGBUILD" ]]; then
    fail "$pkg" "no PKGBUILD on $base_branch"
    continue
  fi

  # The base branch may have moved since the check ran.
  current_version="$(srcinfo_version "$pkg")"
  if [[ "$current_version" != "$repo_version" ]]; then
    printf 'Skipping %s: %s is at %s, published is %s\n' "$pkg" "$base_branch" "$current_version" "$repo_version"
    reset_to_base
    continue
  fi

  if [[ "$(grep -c '^pkgrel=' "$pkg/PKGBUILD")" != 1 ]]; then
    fail "$pkg" "PKGBUILD does not have exactly one top-level pkgrel= line"
    continue
  fi

  old_pkgrel="$(awk '$1 == "pkgrel" { print $3; exit }' "$pkg/.SRCINFO")"
  # Rebuilds go to the next integer release, as in Arch (1 -> 2, 1.1 -> 2).
  new_pkgrel="$((${old_pkgrel%%.*} + 1))"
  sed -i "s/^pkgrel=.*/pkgrel=${new_pkgrel}/" "$pkg/PKGBUILD"

  if ! (cd "$pkg" && makepkg --printsrcinfo >.SRCINFO); then
    fail "$pkg" "makepkg --printsrcinfo failed"
    continue
  fi
  if [[ "$(awk '$1 == "pkgrel" { print $3; exit }' "$pkg/.SRCINFO")" != "$new_pkgrel" ]]; then
    fail "$pkg" "pkgrel in .SRCINFO is not $new_pkgrel after the bump"
    continue
  fi

  new_version="$(srcinfo_version "$pkg")"
  libs_short="$(jq -r '.missing_libs | if length > 3 then (.[0:3] | join(", ")) + ", …" else join(", ") end' <<<"$entry")"
  title="${pkg}: rebuild for ${libs_short}"

  body_file=".ci/pr-bodies/rebuild-${pkg}.md"
  {
    printf 'Automated rebuild.\n\n'
    printf 'Package: `%s`\n' "$pkg"
    printf 'Version: `%s` -> `%s`\n\n' "$repo_version" "$new_version"
    printf 'The published binaries link against shared libraries that are no longer\n'
    printf 'provided by the Arch or CachyOS repositories (found by `repo-manage-util check-rebuild`).\n\n'
    printf 'Missing libraries:\n\n'
    jq -r '.packages[] | "- `\(.pkgname)`: \(.missing_libs | map("`\(.)`") | join(", "))"' <<<"$entry"
  } >"$body_file"

  git add "$pkg/PKGBUILD" "$pkg/.SRCINFO"
  git commit -m "$title"
  # No open PR uses this branch (checked above), so a leftover one can be overwritten.
  git push --force origin "$branch" || { fail "$pkg" "push failed"; continue; }

  gh pr create \
    --title "$title" \
    --body-file "$body_file" \
    --base "$base_branch" \
    --head "$branch" || { fail "$pkg" "gh pr create failed"; continue; }

  count=$((count + 1))
done < <(jq -c '.[]' "$rebuild_json")

reset_to_base
