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
  collab-handoff pickup <id> --from <name>
  collab-handoff close  <id> --from <name>
  collab-handoff cancel <id> --from <name>
EOF
}

[[ $# -ge 1 ]] || { usage; exit 1; }

VERB="create"
case "$1" in
  pickup) VERB="pickup"; ID="$2"; shift 2 ;;
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
    # Find the block across all agent logs (receivers may close handoffs that
    # live in the sender's log; the --from flag identifies the actor, not
    # the host log).
    target_log=""
    for desc in .collab/agents.d/*.yml; do
      [[ -f "$desc" ]] || continue
      base=$(basename "$desc")
      [[ "$base" == _* ]] && continue
      candidate=$(awk -F': *' '/^log_path:/ { print $2 }' "$desc")
      [[ -f "$candidate" ]] || continue
      if grep -q "<!-- collab:handoff:start id=$ID -->" "$candidate"; then
        target_log="$candidate"
        break
      fi
    done
    if [[ -z "$target_log" ]]; then
      echo "handoff: id $ID not found in any agent log" >&2
      exit 1
    fi
    tmp=$(mktemp)
    awk -v id="$ID" -v ns="$newstatus" '
      $0 ~ "<!-- collab:handoff:start id=" id " -->" { in_blk = 1; print; next }
      $0 == "<!-- collab:handoff:end -->" { in_blk = 0; print; next }
      in_blk && /^- \*\*status:\*\*/ { print "- **status:** " ns; next }
      { print }
    ' "$target_log" > "$tmp"
    mv "$tmp" "$target_log"
    echo "handoff $ID -> $newstatus"
    ;;

  pickup)
    # Receiver-side: locate the block (across ALL agent logs, not just sender's),
    # print its summary to stdout, and stamp `picked-up:` metadata onto the block.
    # Status stays `open` until close. Idempotent: re-running on the same id
    # updates the timestamp but produces the same summary.
    NOW=$(bash "$HERE/collab-now.sh")
    found_log=""
    for desc in .collab/agents.d/*.yml; do
      [[ -f "$desc" ]] || continue
      base=$(basename "$desc")
      [[ "$base" == _* ]] && continue
      candidate=$(awk -F': *' '/^log_path:/ { print $2 }' "$desc")
      [[ -f "$candidate" ]] || continue
      if grep -q "<!-- collab:handoff:start id=$ID -->" "$candidate"; then
        found_log="$candidate"
        break
      fi
    done
    if [[ -z "$found_log" ]]; then
      echo "handoff pickup: id $ID not found in any agent log" >&2
      exit 1
    fi

    # Print the block summary to stdout for the receiver to paste into state.md.
    awk -v id="$ID" '
      $0 ~ "<!-- collab:handoff:start id=" id " -->" { in_blk = 1 }
      in_blk { print }
      $0 == "<!-- collab:handoff:end -->" && in_blk { in_blk = 0; exit }
    ' "$found_log"

    # Stamp picked-up metadata. Buffer the target block so we can decide where
    # to place picked-up after seeing the whole thing (idempotent: replaces an
    # existing picked-up line; otherwise inserts after the status line).
    tmp=$(mktemp)
    awk -v id="$ID" -v who="$FROM" -v now="$NOW" '
      $0 ~ "<!-- collab:handoff:start id=" id " -->" {
        in_blk = 1; n = 0; picked_seen = 0
        lines[n++] = $0
        next
      }
      in_blk && $0 == "<!-- collab:handoff:end -->" {
        for (i = 0; i < n; i++) {
          print lines[i]
          if (!picked_seen && lines[i] ~ /^- \*\*status:\*\*/) {
            print "- **picked-up:** " now " by " who
          }
        }
        print
        in_blk = 0
        next
      }
      in_blk {
        if ($0 ~ /^- \*\*picked-up:\*\*/) {
          lines[n++] = "- **picked-up:** " now " by " who
          picked_seen = 1
        } else {
          lines[n++] = $0
        }
        next
      }
      { print }
    ' "$found_log" > "$tmp"
    mv "$tmp" "$found_log"

    # Bump INDEX timestamp so other agents see the activity.
    bash "$HERE/collab-register.sh" "$found_log" >/dev/null 2>&1 || true

    echo "---"
    echo "handoff $ID picked up by $FROM at $NOW"
    ;;
esac
