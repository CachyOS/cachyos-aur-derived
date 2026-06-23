#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

outdated_file=".ci/update-check/outdated.txt"
check_json=".ci/update-check/version-check.json"

if [[ ! -f "$outdated_file" || ! -f "$check_json" ]]; then
  printf 'error: run ci/check-updates.sh before ci/open-update-prs.sh\n' >&2
  exit 1
fi

if [[ ! -s "$outdated_file" ]]; then
  printf 'No package updates found.\n'
  exit 0
fi

base_branch="${BASE_BRANCH:-${GITHUB_REF_NAME:-master}}"
update_limit="${UPDATE_LIMIT:-10}"

git config user.name "${GIT_AUTHOR_NAME:-cachyos-update-bot}"
git config user.email "${GIT_AUTHOR_EMAIL:-cachyos-update-bot@users.noreply.github.com}"
git config --global --add safe.directory "$repo_root"

git fetch origin "$base_branch"

mkdir -p .ci/pr-bodies

count=0
while IFS= read -r pkg; do
  [[ -n "$pkg" ]] || continue
  if ((count >= update_limit)); then
    printf 'Reached UPDATE_LIMIT=%s\n' "$update_limit"
    break
  fi

  old_version="$(jq -r --arg pkg "$pkg" '.[] | select(.pkgbase == $pkg) | .local_version' "$check_json" | tail -n1)"
  new_version="$(jq -r --arg pkg "$pkg" '.[] | select(.pkgbase == $pkg) | .upstream_version' "$check_json" | tail -n1)"
  safe_version="$(printf '%s' "$new_version" | tr -c 'A-Za-z0-9._-' '-')"
  branch="bot/update/${pkg}-${safe_version}"

  printf 'Updating %s: %s -> %s\n' "$pkg" "$old_version" "$new_version"

  git checkout -B "$branch" "origin/$base_branch"

  if ! ci/update-one.sh "$pkg"; then
    printf 'update failed: %s\n' "$pkg" >>.ci/update-check/update-failures.txt
    git checkout -B "$base_branch" "origin/$base_branch"
    continue
  fi

  if git diff --quiet -- "$pkg"; then
    printf 'No diff after update for %s\n' "$pkg"
    git checkout -B "$base_branch" "origin/$base_branch"
    continue
  fi

  body_file=".ci/pr-bodies/${pkg}.md"
  ci/render-pr-body.sh "$pkg" "$old_version" "$new_version" >"$body_file"

  git add "$pkg/PKGBUILD" "$pkg/.SRCINFO"
  git commit -m "${pkg}: update to ${new_version}"
  git push --force-with-lease origin "$branch"

  pr_number="$(gh pr list --head "$branch" --json number --jq '.[0].number // empty')"
  if [[ -n "$pr_number" ]]; then
    gh pr edit "$pr_number" \
      --title "${pkg}: update to ${new_version}" \
      --body-file "$body_file" \
      --base "$base_branch"
  else
    gh pr create \
      --title "${pkg}: update to ${new_version}" \
      --body-file "$body_file" \
      --base "$base_branch" \
      --head "$branch"
  fi

  count=$((count + 1))
done <"$outdated_file"

git checkout -B "$base_branch" "origin/$base_branch"
