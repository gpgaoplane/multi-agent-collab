#!/usr/bin/env bash
# Audit INDEX against filesystem. Prints mismatches and exits non-zero if any.
# Scans under .claude/, .codex/, .gemini/, docs/agents/, .collab/ (excluding archive/).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-check: $INDEX missing" >&2
  exit 2
fi

mismatches=0

# 1. INDEX references → filesystem check
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ ! -f "$path" ]]; then
    echo "MISSING (in INDEX, not on disk): $path"
    mismatches=$((mismatches + 1))
  fi
done < <(idx_list_paths "$INDEX")

# 2. Filesystem scan → INDEX check
scan_dirs=(.claude .codex .gemini docs/agents .collab)
for d in "${scan_dirs[@]}"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r -d '' path; do
    # Skip archive directory and .gitkeep
    case "$path" in
      ./.collab/archive/*) continue ;;
      */.gitkeep) continue ;;
    esac
    # Normalize: strip leading ./
    path="${path#./}"
    if ! idx_get_row "$INDEX" "$path" | grep -q .; then
      # Only flag files with frontmatter (managed)
      if fm_has_frontmatter "$path"; then
        echo "ORPHAN (on disk, not in INDEX): $path"
        mismatches=$((mismatches + 1))
      fi
    fi
  done < <(find "$d" -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) -print0)
done

if [[ $mismatches -eq 0 ]]; then
  echo "OK: INDEX and filesystem aligned"
  exit 0
else
  echo
  echo "$mismatches mismatch(es) found"
  exit 1
fi
