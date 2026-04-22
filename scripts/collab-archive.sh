#!/usr/bin/env bash
# Archive a managed file: move to .collab/archive/<path>, flip status, update INDEX.
# Usage: collab-archive.sh <path>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: collab-archive.sh <existing-path>" >&2
  exit 1
fi

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-archive: $INDEX missing" >&2
  exit 1
fi

ARCHIVE_DIR=".collab/archive"
DEST="$ARCHIVE_DIR/$FILE"

mkdir -p "$(dirname "$DEST")"
mv "$FILE" "$DEST"

# Flip frontmatter status to archived, update timestamp.
NOW=$(bash "$HERE/collab-now.sh")
if fm_has_frontmatter "$DEST"; then
  fm_set_field "$DEST" status archived
  fm_set_field "$DEST" last-updated "$NOW"
fi

# Update INDEX: remove old row, add archived row at new path.
idx_remove "$INDEX" "$FILE"
type=$(fm_get_field "$DEST" type)
owner=$(fm_get_field "$DEST" owner)
: "${type:=unknown}"
: "${owner:=unknown}"
idx_upsert "$INDEX" "$DEST" "$type" "$owner" "archived" "$NOW"

fm_set_field "$INDEX" last-updated "$NOW"

echo "Archived: $FILE -> $DEST"
