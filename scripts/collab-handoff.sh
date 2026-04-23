#!/usr/bin/env bash
# Write or mutate a handoff block in the sender agent's work log.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
TEMPLATE_BLOCK="$SKILL_ROOT/templates/handoff-block.md"
# When installed via npm the template lives next to scripts/
[[ -f "$TEMPLATE_BLOCK" ]] || TEMPLATE_BLOCK="$HERE/../templates/handoff-block.md"

source "$HERE/lib/merge.sh"

usage() {
  cat <<'EOF'
Usage:
  collab-handoff <to-agent> --from <name> [--message "..."] [--parent-id <id>] [--files "a b c"]
  collab-handoff close  <id> --from <name>
  collab-handoff cancel <id> --from <name>
EOF
}

[[ $# -ge 1 ]] || { usage; exit 1; }

VERB="create"
case "$1" in
  close|cancel) VERB="$1"; ID="$2"; shift 2 ;;
  -h|--help) usage; exit 0 ;;
  *) TO_AGENT="$1"; shift ;;
esac

FROM=""; MESSAGE=""; PARENT_ID="none"; FILES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --message) MESSAGE="$2"; shift 2 ;;
    --parent-id) PARENT_ID="$2"; shift 2 ;;
    --files) FILES="$2"; shift 2 ;;
    *) echo "handoff: unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$FROM" ]] || { echo "handoff: --from is required" >&2; exit 1; }

# Resolve sender log path from descriptor.
DESC=".collab/agents.d/${FROM}.yml"
[[ -f "$DESC" ]] || { echo "handoff: no descriptor for sender $FROM at $DESC" >&2; exit 1; }
LOG=$(awk -F': *' '/^log_path:/ { print $2 }' "$DESC")
[[ -f "$LOG" ]] || { echo "handoff: sender log $LOG missing" >&2; exit 1; }

case "$VERB" in
  create)
    [[ -n "${TO_AGENT:-}" ]] || { echo "handoff: target agent required" >&2; exit 1; }
    NOW=$(bash "$HERE/collab-now.sh")
    # id = YYYYMMDD-HHMMSS-<4hex>
    HEX=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 4)
    STAMP=$(echo "$NOW" | sed 's/[-:]//g' | sed 's/T/-/' | cut -d'.' -f1 | cut -c1-15)
    HANDOFF_ID="${STAMP}-${HEX}"
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    [[ -n "$BRANCH" ]] || BRANCH="-"

    files_block="$FILES"
    if [[ -z "$files_block" ]]; then
      files_block="(none declared)"
    fi
    msg_block="${MESSAGE:-(no message provided)}"

    content=$(cat "$TEMPLATE_BLOCK")
    content="${content//\{\{HANDOFF_ID\}\}/$HANDOFF_ID}"
    content="${content//\{\{PARENT_ID\}\}/$PARENT_ID}"
    content="${content//\{\{FROM_AGENT\}\}/$FROM}"
    content="${content//\{\{TO_AGENT\}\}/$TO_AGENT}"
    content="${content//\{\{BRANCH\}\}/$BRANCH}"
    content="${content//\{\{TIMESTAMP\}\}/$NOW}"
    content="${content//\{\{MESSAGE\}\}/$msg_block}"
    content="${content//\{\{FILES_TOUCHED\}\}/$files_block}"

    printf '\n%s\n' "$content" >> "$LOG"

    # Drop the sender from ACTIVE.md (their session ends with this handoff).
    # Do NOT write a receiver row — ACTIVE.md = running sessions only.
    bash "$HERE/collab-presence.sh" end --agent "$FROM" --session "handoff-$HANDOFF_ID" 2>/dev/null || true

    # Bump INDEX last-updated for sender's log so receivers see a delta.
    bash "$HERE/collab-register.sh" "$LOG" >/dev/null 2>&1 || true

    echo "$HANDOFF_ID"
    ;;

  close|cancel)
    newstatus=$([ "$VERB" = "close" ] && echo "closed" || echo "cancelled")
    tmp=$(mktemp)
    awk -v id="$ID" -v ns="$newstatus" '
      $0 ~ "<!-- collab:handoff:start id=" id " -->" { in_blk = 1; print; next }
      $0 == "<!-- collab:handoff:end -->" { in_blk = 0; print; next }
      in_blk && /^- \*\*status:\*\*/ { print "- **status:** " ns; next }
      { print }
    ' "$LOG" > "$tmp"
    if ! grep -q "handoff:start id=$ID" "$tmp"; then
      echo "handoff: id $ID not found in $LOG" >&2
      rm -f "$tmp"
      exit 1
    fi
    mv "$tmp" "$LOG"
    echo "handoff $ID -> $newstatus"
    ;;
esac
