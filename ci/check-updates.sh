#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mkdir -p .ci/update-check
: >.ci/update-check/version-check.jsonl
: >.ci/update-check/pkgctl-stderr.log
: >.ci/update-check/batch-failures.txt

if (($#)); then
  packages=("$@")
else
  mapfile -t packages < <(ci/list-packages.sh)
fi

batch_size="${BATCH_SIZE:-40}"
batch_sleep="${BATCH_SLEEP:-0}"

if ((${#packages[@]} == 0)); then
  printf '[]\n' >.ci/update-check/version-check.json
  : >.ci/update-check/outdated.txt
  : >.ci/update-check/failures.tsv
  exit 0
fi

for ((i = 0; i < ${#packages[@]}; i += batch_size)); do
  batch=("${packages[@]:i:batch_size}")
  tmp_json="$(mktemp)"
  tmp_err="$(mktemp)"

  if ! pkgctl version check --json --verbose "${batch[@]}" >"$tmp_json" 2>"$tmp_err"; then
    printf 'batch failed: %s\n' "${batch[*]}" >>.ci/update-check/batch-failures.txt
  fi

  cat "$tmp_err" >>.ci/update-check/pkgctl-stderr.log

  if jq -e 'type == "array"' "$tmp_json" >/dev/null 2>&1; then
    jq -c '.[]' "$tmp_json" >>.ci/update-check/version-check.jsonl
  else
    {
      printf 'invalid json batch: %s\n' "${batch[*]}"
      sed -n '1,120p' "$tmp_json"
      sed -n '1,120p' "$tmp_err"
    } >>.ci/update-check/batch-failures.txt
  fi

  rm -f "$tmp_json" "$tmp_err"

  if ((batch_sleep > 0 && i + batch_size < ${#packages[@]})); then
    sleep "$batch_sleep"
  fi
done

jq -s 'sort_by(.pkgbase)' .ci/update-check/version-check.jsonl >.ci/update-check/version-check.json
jq -r '.[] | select(.out_of_date == true) | .pkgbase' .ci/update-check/version-check.json >.ci/update-check/outdated.txt
jq -r '.[] | select(.status != "success") | [.pkgbase, (.message // "unknown failure")] | @tsv' \
  .ci/update-check/version-check.json >.ci/update-check/failures.tsv

{
  printf '## AUR update check\n\n'
  printf -- '- Checked packages: %s\n' "${#packages[@]}"
  printf -- '- Out-of-date: %s\n' "$(wc -l <.ci/update-check/outdated.txt)"
  printf -- '- Failures: %s\n' "$(wc -l <.ci/update-check/failures.tsv)"
  if [[ -s .ci/update-check/outdated.txt ]]; then
    printf '\n### Out-of-date\n\n```text\n'
    cat .ci/update-check/outdated.txt
    printf '```\n'
  fi
  if [[ -s .ci/update-check/failures.tsv ]]; then
    printf '\n### Failures\n\n```text\n'
    cat .ci/update-check/failures.tsv
    printf '```\n'
  fi
} >.ci/update-check/summary.md

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat .ci/update-check/summary.md >>"$GITHUB_STEP_SUMMARY"
fi
