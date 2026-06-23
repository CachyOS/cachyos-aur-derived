#!/usr/bin/env bash
set -euo pipefail

if (($# != 3)); then
  printf 'usage: %s <package-dir> <old-version> <new-version>\n' "$0" >&2
  exit 2
fi

pkg="$1"
old_version="$2"
new_version="$3"

risk_flags=()

if git diff --name-only -- "$pkg" | grep -Eq '\.install$'; then
  risk_flags+=(".install changed")
fi

if git diff -U0 -- "$pkg/PKGBUILD" | grep -Eq '^[+-][[:space:]]*install='; then
  risk_flags+=("install= changed")
fi

if git diff -U0 -- "$pkg/PKGBUILD" | grep -Eq '^[+-][[:space:]]*(source|source_[[:alnum:]_]+)='; then
  risk_flags+=("source array changed")
fi

if git diff -U0 -- "$pkg/PKGBUILD" | grep -Eq '^[+].*SKIP'; then
  risk_flags+=("new SKIP checksum text in PKGBUILD diff")
fi

if git diff -U0 -- "$pkg" | grep -Eq '^[+].*(curl|wget|git clone|systemctl|useradd|groupadd|setcap|modprobe|rm[[:space:]]+-rf)'; then
  risk_flags+=("sensitive command appears in added lines")
fi

cat <<EOF
Automated package update.

Package: \`$pkg\`
Version: \`$old_version\` -> \`$new_version\`

Checks:
- \`pkgctl version upgrade\`: completed
- checksums: updated by \`pkgctl version upgrade\`
- \`.SRCINFO\`: regenerated
- \`makepkg --verifysource\`: ${VERIFY_SOURCE:-false}

Risk flags:
EOF

if ((${#risk_flags[@]} == 0)); then
  printf -- '- none detected by static diff scan\n'
else
  for flag in "${risk_flags[@]}"; do
    printf -- '- %s\n' "$flag"
  done
fi

cat <<EOF

Diff summary:

\`\`\`text
$(git diff --stat -- "$pkg")
\`\`\`
EOF
