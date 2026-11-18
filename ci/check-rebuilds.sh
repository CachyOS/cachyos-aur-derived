#!/usr/bin/env bash
# Find aur-derived packages whose published binaries link against shared
# libraries that no longer exist in the repositories (soname bumps), using
# `repo-manage-util check-rebuild`.
#
# Outputs (in .ci/rebuild-check/):
#   rebuild.json  - pkgbases that need a pkgrel bump, with missing libraries
#   rebuild.txt   - the same pkgbases, one per line
#   skipped.tsv   - broken pkgbases that are skipped and why
#   summary.md    - human readable summary
set -euo pipefail
export LC_ALL=C

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

out_dir=".ci/rebuild-check"
work_dir="${REBUILD_WORKDIR:-.ci/rebuild-work}"
cachyos_mirror="${CACHYOS_MIRROR:-https://mirror.cachyos.org/repo}"
cachyos_repo="${CACHYOS_REPO:-cachyos}"
arch_mirror="${ARCH_MIRROR:-https://geo.mirror.pkgbuild.com}"
arch="x86_64"
rmu="${REPO_MANAGE_UTIL:-repo-manage-util}"
download_jobs="${DOWNLOAD_JOBS:-8}"
ignore_file="ci/rebuild-ignore.txt"

mkdir -p "$out_dir" "$work_dir/db" "$work_dir/pkgs"
work_dir="$(realpath "$work_dir")"
: >"$out_dir/skipped.tsv"

if (($#)); then
  packages=("$@")
else
  mapfile -t packages < <(ci/list-packages.sh)
fi

# pkgname <TAB> pkgbase <TAB> full version, from the checked-out .SRCINFO files
local_map="$work_dir/local-packages.tsv"
: >"$local_map"
for pkg in "${packages[@]}"; do
  [[ -f "$pkg/.SRCINFO" ]] || { printf 'warning: %s/.SRCINFO missing\n' "$pkg" >&2; continue; }
  awk -v dir="$pkg" '
    $1 == "pkgver" { ver = $3 }
    $1 == "pkgrel" && !rel { rel = $3 }
    $1 == "epoch" && !ep { ep = $3 }
    $1 == "pkgname" { names[++n] = $3 }
    END {
      full = (ep ? ep ":" : "") ver "-" rel
      for (i = 1; i <= n; i++) print names[i] "\t" dir "\t" full
    }' "$pkg/.SRCINFO" >>"$local_map"
done

# Published packages: pkgname <TAB> version <TAB> arch <TAB> filename <TAB> sha256
db_dir="$work_dir/db/$cachyos_repo"
rm -rf "$db_dir"
mkdir -p "$db_dir"
curl -fsSL --retry 3 -o "$work_dir/db/$cachyos_repo.db" \
  "$cachyos_mirror/$arch/$cachyos_repo/$cachyos_repo.db"
tar -xf "$work_dir/db/$cachyos_repo.db" -C "$db_dir"

repo_map="$work_dir/repo-packages.tsv"
find "$db_dir" -name desc -print0 \
  | xargs -0 awk '
      FNR == 1 && name { print name "\t" ver "\t" a "\t" file "\t" sum; name = "" }
      /^%NAME%$/ { getline; name = $0 }
      /^%VERSION%$/ { getline; ver = $0 }
      /^%ARCH%$/ { getline; a = $0 }
      /^%FILENAME%$/ { getline; file = $0 }
      /^%SHA256SUM%$/ { getline; sum = $0 }
      END { if (name) print name "\t" ver "\t" a "\t" file "\t" sum }' \
  | sort >"$repo_map"

# Only ELF-carrying (non-"any") packages built from this repository matter.
wanted="$work_dir/wanted.tsv"
join -t $'\t' <(cut -f1 "$local_map" | sort -u) "$repo_map" \
  | awk -F'\t' '$3 != "any"' >"$wanted"

printf 'Downloading %s published packages from [%s]\n' "$(wc -l <"$wanted")" "$cachyos_repo"

# Drop stale files from earlier runs so they are not analyzed.
declare -A keep=()
while IFS=$'\t' read -r _ _ _ file _; do keep["$file"]=1; done <"$wanted"
for f in "$work_dir"/pkgs/*.pkg.tar.zst; do
  [[ -e "$f" ]] || continue
  [[ -n "${keep[${f##*/}]:-}" ]] || rm -f "$f"
done

awk -F'\t' '{ print $4 }' "$wanted" \
  | while read -r file; do
      [[ -s "$work_dir/pkgs/$file" ]] || printf '%s\n' "$file"
    done \
  | xargs -r -P "$download_jobs" -I{} \
      curl -fsSL --retry 3 -o "$work_dir/pkgs/{}" "$cachyos_mirror/$arch/$cachyos_repo/{}"

(
  cd "$work_dir/pkgs"
  awk -F'\t' '{ print $5 "  " $4 }' "$wanted" | sha256sum --quiet -c -
)

# Resolve sonames against Arch + the CachyOS repo itself (other CachyOS
# packages provide libraries that aur-derived packages link to).
cat >"$work_dir/pacman.conf" <<EOF
[options]
Architecture = $arch
SigLevel = Never

[core]
Server = $arch_mirror/\$repo/os/\$arch

[extra]
Server = $arch_mirror/\$repo/os/\$arch

[multilib]
Server = $arch_mirror/\$repo/os/\$arch

[$cachyos_repo]
Server = $cachyos_mirror/\$arch/\$repo
EOF

"$rmu" check-rebuild \
  --repo-dir "$work_dir/pkgs" \
  --pacman-conf "$work_dir/pacman.conf" \
  --json "$out_dir/broken.json"

# Group broken pkgnames by pkgbase and apply the ignore list.
ignore_json='[]'
if [[ -f "$ignore_file" ]]; then
  ignore_json="$(
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$ignore_file" \
      | jq -R -s 'split("\n") | map(select(length > 0) | split(" ") | map(select(length > 0)) | {pkgbase: .[0], lib: (.[1] // null)})'
  )"
fi

jq -n \
  --slurpfile broken "$out_dir/broken.json" \
  --rawfile local_map "$local_map" \
  --rawfile repo_map "$repo_map" \
  --argjson ignore "$ignore_json" '
  def tsv: split("\n") | map(select(length > 0) | split("\t"));
  ($local_map | tsv | map({key: .[0], value: {pkgbase: .[1], version: .[2]}}) | from_entries) as $local
  | ($repo_map | tsv | map({key: .[0], value: .[1]}) | from_entries) as $repo
  | def ignored($base; $lib):
      any($ignore[]; . as $e | $e.pkgbase == $base
        and ($e.lib == null or ($lib | test("^" + ($e.lib | gsub("\\."; "\\.") | gsub("\\*"; ".*")) + "$"))));
  [ $broken[0][]
    | . as $b
    | $local[$b.name] as $l
    | select($l != null)
    | { pkgbase: $l.pkgbase,
        pkgname: $b.name,
        local_version: $l.version,
        repo_version: ($repo[$b.name] // $b.version),
        missing_libs: [ $b.missing_libs[] | select(ignored($l.pkgbase; .) | not) ] }
    | select(.missing_libs | length > 0) ]
  | group_by(.pkgbase)
  | map({
      pkgbase: .[0].pkgbase,
      local_version: .[0].local_version,
      repo_version: .[0].repo_version,
      packages: map({pkgname, missing_libs}),
      missing_libs: (map(.missing_libs[]) | unique)
    })' >"$out_dir/candidates.json"

# A pkgbase whose PKGBUILD version differs from the published one was already
# bumped (update or rebuild) and is just waiting for the build server.
jq '[.[] | select(.local_version == .repo_version)]' "$out_dir/candidates.json" >"$out_dir/rebuild.json"
jq -r '.[] | select(.local_version != .repo_version)
  | [.pkgbase, "PKGBUILD \(.local_version) != published \(.repo_version) (pending build)"] | @tsv' \
  "$out_dir/candidates.json" >>"$out_dir/skipped.tsv"
jq -r '.[].pkgbase' "$out_dir/rebuild.json" >"$out_dir/rebuild.txt"

{
  printf '## Rebuild check\n\n'
  printf -- '- Published packages analyzed: %s\n' "$(wc -l <"$wanted")"
  printf -- '- Need rebuild: %s\n' "$(wc -l <"$out_dir/rebuild.txt")"
  printf -- '- Skipped: %s\n' "$(wc -l <"$out_dir/skipped.tsv")"
  if [[ -s "$out_dir/rebuild.txt" ]]; then
    printf '\n### Need rebuild\n\n```text\n'
    jq -r '.[] | "\(.pkgbase) \(.repo_version): \(.missing_libs | join(", "))"' "$out_dir/rebuild.json"
    printf '```\n'
  fi
  if [[ -s "$out_dir/skipped.tsv" ]]; then
    printf '\n### Skipped\n\n```text\n'
    cat "$out_dir/skipped.tsv"
    printf '```\n'
  fi
} >"$out_dir/summary.md"

cat "$out_dir/summary.md"
