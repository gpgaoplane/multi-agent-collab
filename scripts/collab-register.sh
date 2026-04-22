#!/usr/bin/env bash
# Register a file in .collab/INDEX.md using its frontmatter metadata.
# Usage: collab-register.sh <relative-path-to-file>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
  echo "Usage: collab-register.sh <path>" >&2
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo "collab-register: file not found: $FILE" >&2
  exit 1
fi

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-register: $INDEX not found (run collab-init first)" >&2
  exit 1
fi

if ! fm_has_frontmatter "$FILE"; then
  echo "collab-register: $FILE has no frontmatter" >&2
  exit 1
fi

type=$(fm_get_field "$FILE" type)
owner=$(fm_get_field "$FILE" owner)
status=$(fm_get_field "$FILE" status)
last_updated=$(fm_get_field "$FILE" last-updated)

: "${type:=unknown}"
: "${owner:=unknown}"
: "${status:=active}"
: "${last_updated:=$(bash "$HERE/collab-now.sh")}"

idx_upsert "$INDEX" "$FILE" "$type" "$owner" "$status" "$last_updated"

# Also update INDEX's own last-updated stamp.
fm_set_field "$INDEX" last-updated "$(bash "$HERE/collab-now.sh")"

echo "Registered: $FILE"
