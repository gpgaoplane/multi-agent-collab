#!/usr/bin/env bash
# Write/remove a row in .collab/ACTIVE.md for the invoking agent.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/merge.sh"

ACTIVE=".collab/ACTIVE.md"

usage() {
  cat <<'EOF'
Usage:
  collab-presence start --agent <name> [--session <id>] [--branch <name>]
  collab-presence end   --agent <name> [--session <id>]
EOF
}

[[ $# -ge 1 ]] || { usage; exit 1; }
verb="$1"; shift

AGENT=""; SESSION="$$"; BRANCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$AGENT" ]] || { echo "presence: --agent is required" >&2; exit 1; }
[[ -f "$ACTIVE" ]] || { echo "presence: $ACTIVE not found. Run collab-init first." >&2; exit 1; }

if [[ -z "$BRANCH" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")
fi
NOW=$(bash "$HERE/collab-now.sh")

read_section() {
  awk -v s="<!-- collab:active:start -->" -v e="<!-- collab:active:end -->" '
    $0 == s { in_sec = 1; next }
    $0 == e { in_sec = 0; next }
    in_sec { print }
  ' "$ACTIVE"
}

write_section() {
  local body="$1"
  merge_replace_section "$ACTIVE" "active" "$body"
}

current=$(read_section)
# Strip any existing row for this (agent, session).
filtered=$(printf '%s\n' "$current" | awk -v a="$AGENT" -v s="$SESSION" '
  BEGIN { FS="|" }
  $0 !~ /^\|/ { print; next }
  /^\| agent / { print; next }
  /^\|[-| ]+\|?$/ { print; next }   # separator row; do NOT strip
  {
    gsub(/^ *| *$/, "", $2); gsub(/^ *| *$/, "", $3)
    if ($2 == a && $3 == s) next
    print
  }
')

case "$verb" in
  start)
    row="| $AGENT | $SESSION | $BRANCH | $NOW |"
    if [[ -z "$filtered" ]]; then
      new="$row"
    else
      new=$(printf '%s\n%s' "$filtered" "$row")
    fi
    write_section "$new"
    ;;
  end)
    write_section "$filtered"
    ;;
  *) usage; exit 1 ;;
esac
