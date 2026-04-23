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
# Naive YAML read — relies on `memory_dir: <unquoted-path>` convention used by
# all shipped descriptors. If descriptors adopt quoted values or embedded colons,
# switch to a real YAML parser.
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
  # Verify the rewrite actually produced the new watermark line.
  if ! grep -q "Last read INDEX at: $NOW" "$tmp"; then
    rm -f "$tmp"
    echo "catchup ack: $STATE has no 'Last read INDEX at:' line inside the read-watermark section; cannot update" >&2
    exit 1
  fi
  mv "$tmp" "$STATE"
  echo "watermark updated: $NOW"
  exit 0
fi

# Preview mode: print INDEX rows whose last-updated is newer than WATERMARK.

# Detect GNU date ONCE. macOS without coreutils lacks -d; Git Bash on Windows
# ships GNU date; Linux is fine. Without GNU date we cannot parse ISO-8601 with
# tz offsets reliably, so we over-report (print everything) rather than silently
# under-report (print nothing).
_date_cmd=""
if date -d "2020-01-01" +%s >/dev/null 2>&1; then
  _date_cmd=date
elif command -v gdate >/dev/null 2>&1 && gdate -d "2020-01-01" +%s >/dev/null 2>&1; then
  _date_cmd=gdate
fi

if [[ -z "$_date_cmd" ]]; then
  echo "catchup: warning — GNU date not available; printing all INDEX entries (install coreutils for delta-read)" >&2
  # Print all rows — over-report failure mode (agent sees too much, never too little).
  found=0
  while IFS=$'\t' read -r path updated; do
    [[ -z "$path" ]] && continue
    printf '%s\t%s\n' "$path" "$updated"
    found=1
  done < <(idx_list_with_timestamps "$INDEX")
  [[ $found -eq 0 ]] && echo "up to date"
  exit 0
fi

ts_to_epoch() {
  local ts="$1"
  [[ -z "$ts" || "$ts" == "(not yet read)" ]] && { echo 0; return; }
  local out
  if out=$("$_date_cmd" -d "$ts" +%s 2>/dev/null); then
    echo "$out"
  else
    # Parseable by our tool but malformed value — treat row as "newer than
    # anything" so it's surfaced rather than hidden.
    echo 9999999999
  fi
}

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
