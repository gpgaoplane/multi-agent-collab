#!/usr/bin/env bash
# Print INDEX entries newer than the caller agent's watermark.
# Dry by default — use `collab-catchup ack` to commit the watermark.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/index.sh"

INDEX=".collab/INDEX.md"
AGENT=""; VERB="preview"; STATE_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage:
  collab-catchup [preview] --agent <name>         # default — print newer entries
  collab-catchup ack --agent <name>               # commit current time as watermark
EOF
}

[[ $# -ge 1 ]] || { usage; exit 1; }
case "$1" in
  ack) VERB="ack"; shift ;;
  preview) VERB="preview"; shift ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --state) STATE_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "catchup: unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$AGENT" ]] || { echo "catchup: --agent required" >&2; exit 1; }
[[ -f "$INDEX" ]] || { echo "catchup: $INDEX missing" >&2; exit 1; }

# Locate the agent's state.md via descriptor.
DESC=".collab/agents.d/${AGENT}.yml"
[[ -f "$DESC" ]] || { echo "catchup: no descriptor for agent $AGENT" >&2; exit 1; }
STATE=$(awk -F': *' '/^memory_dir:/ { print $2 }' "$DESC")
STATE="${STATE_OVERRIDE:-$STATE/state.md}"

[[ -f "$STATE" ]] || { echo "catchup: state file $STATE missing" >&2; exit 1; }

WATERMARK=$(awk '
  /<!-- section:read-watermark:start -->/ { in_sec = 1; next }
  /<!-- section:read-watermark:end -->/ { in_sec = 0 }
  in_sec && /Last read INDEX at:/ { sub(/^Last read INDEX at: */, ""); print; exit }
' "$STATE")

if [[ "$VERB" == "ack" ]]; then
  NOW=$(bash "$HERE/collab-now.sh")
  tmp=$(mktemp)
  awk -v now="$NOW" '
    /<!-- section:read-watermark:start -->/ { print; in_sec = 1; next }
    /<!-- section:read-watermark:end -->/ { in_sec = 0 }
    in_sec && /Last read INDEX at:/ { print "Last read INDEX at: " now; next }
    { print }
  ' "$STATE" > "$tmp"
  mv "$tmp" "$STATE"
  echo "watermark updated: $NOW"
  exit 0
fi

# Preview mode: print INDEX rows whose last-updated is newer than WATERMARK.
# ts_to_epoch normalizes both sides to UTC, so cross-tz authorship is safe.

ts_to_epoch() {
  # Convert ISO-8601 (with tz offset) to UTC epoch seconds.
  # Returns 0 for "(not yet read)", empty, or unparseable input (safe over-report).
  local ts="$1"
  [[ -z "$ts" || "$ts" == "(not yet read)" ]] && { echo 0; return; }
  local out
  if out=$(date -d "$ts" +%s 2>/dev/null); then
    echo "$out"
  elif command -v gdate >/dev/null 2>&1 && out=$(gdate -d "$ts" +%s 2>/dev/null); then
    echo "$out"
  else
    echo 0   # degrades to "newer than anything" — never under-reports changes
  fi
}

# Numeric-only guard for arithmetic compare (any garbage → 0).
numeric_or_zero() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }

wm_epoch=$(numeric_or_zero "$(ts_to_epoch "$WATERMARK")")

found=0
while IFS=$'\t' read -r path updated; do
  [[ -z "$path" ]] && continue
  u_epoch=$(numeric_or_zero "$(ts_to_epoch "$updated")")
  if (( u_epoch > wm_epoch )); then
    printf '%s\t%s\n' "$path" "$updated"
    found=1
  fi
done < <(idx_list_with_timestamps "$INDEX")

if [[ $found -eq 0 ]]; then
  echo "up to date"
fi
