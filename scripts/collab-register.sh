#!/usr/bin/env bash
# Register a file in .collab/INDEX.md.
# Usage: collab-register.sh <path> [--type <t>] [--owner <o>] [--status <s>]
#
# Without flags, metadata is read from the file's YAML frontmatter and the
# script errors out if frontmatter is absent. The flags let you register a
# file that lacks frontmatter (custom logs, ad-hoc artifacts, files generated
# by other tooling) without first having to add a header.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

FILE=""
OPT_TYPE=""
OPT_OWNER=""
OPT_STATUS=""

usage() {
  cat <<'EOF'
Usage: collab-register.sh <path> [--type <t>] [--owner <o>] [--status <s>]

Registers a file in .collab/INDEX.md. By default reads frontmatter from
the file. Use the flags to override or supply missing fields when the
file lacks frontmatter.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)   OPT_TYPE="$2"; shift 2 ;;
    --owner)  OPT_OWNER="$2"; shift 2 ;;
    --status) OPT_STATUS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "collab-register: unknown flag $1" >&2; exit 1 ;;
    *) FILE="$1"; shift ;;
  esac
done

if [[ -z "$FILE" ]]; then
  usage >&2
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

# Frontmatter is the default source of truth, but flags override.
type=""
owner=""
status=""
last_updated=""

if fm_has_frontmatter "$FILE"; then
  type=$(fm_get_field "$FILE" type)
  owner=$(fm_get_field "$FILE" owner)
  status=$(fm_get_field "$FILE" status)
  last_updated=$(fm_get_field "$FILE" last-updated)
fi

# Apply flag overrides (and supply values for files lacking frontmatter).
[[ -n "$OPT_TYPE"   ]] && type="$OPT_TYPE"
[[ -n "$OPT_OWNER"  ]] && owner="$OPT_OWNER"
[[ -n "$OPT_STATUS" ]] && status="$OPT_STATUS"

# Reject if neither frontmatter nor flags supplied any metadata at all.
if [[ -z "$type" && -z "$owner" && -z "$status" ]]; then
  echo "collab-register: $FILE has no frontmatter and no --type/--owner/--status flags supplied" >&2
  exit 1
fi

: "${type:=unknown}"
: "${owner:=unknown}"
: "${status:=active}"
: "${last_updated:=$(bash "$HERE/collab-now.sh")}"

idx_upsert "$INDEX" "$FILE" "$type" "$owner" "$status" "$last_updated"

# Also update INDEX's own last-updated stamp.
fm_set_field "$INDEX" last-updated "$(bash "$HERE/collab-now.sh")"

echo "Registered: $FILE"
