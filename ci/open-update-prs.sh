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
: >.ci/update-check/update-failures.txt

close_superseded_update_prs() {
  local pkg="$1"
  local current_branch="$2"
  local new_version="$3"
  local current_pr_number="$4"
  local pr_limit="${SUPERSEDED_PR_LIMIT:-200}"
  local open_prs_json
  local replacement
  local pr
  local superseded_prs=()

  if [[ -n "$current_pr_number" ]]; then
    replacement="#${current_pr_number}"
  else
    replacement="$current_branch"
  fi

  if ! open_prs_json="$(
    gh pr list \
      --state open \
      --limit "$pr_limit" \
      --json number,headRefName,title
  )"; then
    printf 'warning: unable to list open PRs while checking superseded updates for %s\n' "$pkg" >&2
    return 0
  fi

  mapfile -t superseded_prs < <(
    jq -r \
      --arg pkg "$pkg" \
      --arg current_branch "$current_branch" \
      '.[] | select(.headRefName != $current_branch) | select(.headRefName | startswith("bot/update/")) | select(.title | startswith($pkg + ": update to ")) | [.number, .headRefName] | @tsv' \
      <<<"$open_prs_json"
  )

  for pr in "${superseded_prs[@]}"; do
    local pr_number="${pr%%$'\t'*}"
    local pr_branch="${pr#*$'\t'}"

    printf 'Closing superseded PR #%s for %s from branch %s\n' "$pr_number" "$pkg" "$pr_branch"
    if ! gh pr close "$pr_number" \
      --comment "Superseded by ${replacement} for ${pkg} ${new_version}." \
      --delete-branch; then
      printf 'warning: failed to close superseded PR #%s for %s\n' "$pr_number" "$pkg" >&2
    fi
  done
}

reset_to_base() {
  git checkout -B "$base_branch" "origin/$base_branch"
  git reset --hard "origin/$base_branch"
}

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
  git reset --hard "origin/$base_branch"

  if ! ci/update-one.sh "$pkg"; then
    printf 'update failed: %s\n' "$pkg" >>.ci/update-check/update-failures.txt
    printf 'Update failed for %s\n' "$pkg" >&2
    reset_to_base
    continue
  fi

  if git diff --quiet -- "$pkg"; then
    printf 'No diff after update for %s\n' "$pkg"
    reset_to_base
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
    pr_number="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')"
  fi

  close_superseded_update_prs "$pkg" "$branch" "$new_version" "$pr_number"

  count=$((count + 1))
done <"$outdated_file"

reset_to_base
