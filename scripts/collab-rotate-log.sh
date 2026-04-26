#!/usr/bin/env bash
# collab-rotate-log.sh — archive older entries in an agent's work log.
#
# Detection contract: an entry header is `^## ` followed by an ISO-8601
# timestamp on the same line. Other `## ` headings (e.g. `## Files`,
# `## Notes`, `## Handoff blocks`) inside or around an entry are NOT entry
# boundaries. ANY future change to entry header format must update this regex.
#
# Behavior:
# - Reads rotate_at_lines + rotate_keep_recent from .collab/config.yml
#   (defaults 300 / 8 if absent).
# - Normalizes CRLF→LF for processing; restores original line endings on write.
# - Older entries (everything before the last `keep_recent`) move verbatim to
#   .collab/archive/agents/<agent>-<YYYYMMDD>.md with archived frontmatter.
# - In the live log, archived entries are replaced with one-line summaries
#   inside <!-- collab:log-archived-summary --> markers.
# - Handoff blocks are NEVER archived — they're load-bearing across agents.
#   They stay in place wherever they are (typically end of file).
#
# Idempotent: a log already at-or-below threshold is a no-op.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/merge.sh"

usage() {
  cat <<'EOF'
Usage:
  collab-rotate-log.sh <agent-name> [--threshold N] [--keep N] [--dry-run]
EOF
}

[[ $# -ge 1 ]] || { usage; exit 1; }
AGENT="$1"; shift

THRESHOLD=""
KEEP=""
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --keep) KEEP="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "rotate: unknown arg: $1" >&2; exit 1 ;;
  esac
done

DESC=".collab/agents.d/${AGENT}.yml"
[[ -f "$DESC" ]] || { echo "rotate: no descriptor for $AGENT at $DESC" >&2; exit 1; }
LOG=$(awk -F': *' '/^log_path:/ { print $2 }' "$DESC")
[[ -f "$LOG" ]] || { echo "rotate: log $LOG missing" >&2; exit 1; }

CFG=".collab/config.yml"
if [[ -z "$THRESHOLD" ]]; then
  THRESHOLD=$(awk -F': *' '/^rotate_at_lines:/ { print $2; exit }' "$CFG" 2>/dev/null || true)
  THRESHOLD="${THRESHOLD:-300}"
fi
if [[ -z "$KEEP" ]]; then
  KEEP=$(awk -F': *' '/^rotate_keep_recent:/ { print $2; exit }' "$CFG" 2>/dev/null || true)
  KEEP="${KEEP:-8}"
fi

# Normalize line endings for reliable counting and regex matching.
had_crlf=0
if grep -q $'\r' "$LOG"; then had_crlf=1; fi
tmp_norm=$(mktemp)
tr -d '\r' < "$LOG" > "$tmp_norm"

linecount=$(wc -l < "$tmp_norm" | tr -d ' ')
if [[ $linecount -le $THRESHOLD ]]; then
  rm -f "$tmp_norm"
  echo "rotate: $LOG is $linecount lines (threshold $THRESHOLD); nothing to do."
  exit 0
fi

# Locate ALL entry header lines (anywhere in file). Entries are demarcated by
# `^## YYYY-MM-DDTHH:MM:SS...` headers.
ENTRY_RE='^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
mapfile -t entry_starts < <(awk -v re="$ENTRY_RE" '$0 ~ re { print NR }' "$tmp_norm")

if [[ ${#entry_starts[@]} -le $KEEP ]]; then
  rm -f "$tmp_norm"
  echo "rotate: only ${#entry_starts[@]} entries (keep $KEEP); nothing to archive."
  exit 0
fi

total=${#entry_starts[@]}
cut_idx=$((total - KEEP))
archive_start_line=${entry_starts[0]}
# Archive ends at the line BEFORE the first kept entry.
keep_first_line=${entry_starts[cut_idx]}
archive_end_line=$((keep_first_line - 1))

archived_block=$(sed -n "${archive_start_line},${archive_end_line}p" "$tmp_norm")

# Build per-entry summaries (date — file list from Receipt).
summaries=$(printf '%s\n' "$archived_block" | awk -v re="$ENTRY_RE" '
  function emit(h, files,    d) {
    if (h == "") return
    sub(/^## /, "", h)
    d = substr(h, 1, 10)
    if (files == "") print "- " d " — (no receipt)"
    else print "- " d " — " files
  }
  $0 ~ re {
    emit(header, receipt_files)
    header = $0
    receipt_files = ""
    in_receipt = 0
    next
  }
  /^### Task Receipt/ { in_receipt = 1; next }
  in_receipt && /^- / {
    line = $0
    sub(/^- /, "", line)
    sub(/ \.+ .*$/, "", line)
    if (receipt_files == "") receipt_files = line
    else receipt_files = receipt_files ", " line
    next
  }
  in_receipt && /^$/ { in_receipt = 0 }
  END { emit(header, receipt_files) }
')

NOW_DATE=$(date +%Y%m%d)
ARCHIVE_DIR=".collab/archive/agents"
ARCHIVE_FILE="$ARCHIVE_DIR/${AGENT}-${NOW_DATE}.md"

if [[ $DRY -eq 1 ]]; then
  echo "rotate: would archive ${cut_idx} entries to $ARCHIVE_FILE"
  echo "rotate: would keep $KEEP recent entries in $LOG"
  rm -f "$tmp_norm"
  exit 0
fi

mkdir -p "$ARCHIVE_DIR"
{
  printf -- '---\n'
  printf 'status: archived\n'
  printf 'type: work-log\n'
  printf 'owner: %s\n' "$AGENT"
  printf 'last-updated: %s\n' "$(bash "$HERE/collab-now.sh")"
  printf 'read-if: "researching historical context from %s before %s"\n' "$AGENT" "$NOW_DATE"
  printf 'skip-if: "you only need recent activity"\n'
  printf -- '---\n\n'
  printf '# %s — Archived entries (rotated %s)\n\n' "$AGENT" "$NOW_DATE"
  printf '%s\n' "$archived_block"
} > "$ARCHIVE_FILE"

# Build new live log: same content as tmp_norm, but lines from archive_start_line
# through archive_end_line are deleted; summaries are inserted inside the
# <!-- collab:log-archived-summary --> markers (replacing prior summary content).
new_log=$(mktemp)
sed -n "1,$((archive_start_line - 1))p; ${keep_first_line},\$p" "$tmp_norm" > "$new_log.body"

# Insert summaries inside the archived-summary marker section. If markers don't
# exist yet (legacy log), insert a fresh marker block right after the first
# `---` separator following the work-log header.
if grep -q '<!-- collab:log-archived-summary:start -->' "$new_log.body"; then
  # Replace existing summary section content with the new combined summaries.
  # Read existing summary content and prepend new summaries to it (oldest first
  # at top is the natural read order since archives are append-only).
  existing=$(awk '/<!-- collab:log-archived-summary:start -->/,/<!-- collab:log-archived-summary:end -->/' "$new_log.body" | sed '1d;$d')
  # Strip the placeholder comment if it's the only content.
  if echo "$existing" | grep -qE '^<!-- Older entries' && [[ $(echo "$existing" | grep -c .) -le 3 ]]; then
    existing=""
  fi
  combined="$summaries"
  if [[ -n "$existing" ]]; then
    combined="$existing"$'\n'"$summaries"
  fi
  merge_replace_section "$new_log.body" "log-archived-summary" "$combined"
else
  # Legacy log: inject a marker block right after the first '---' separator.
  awk -v summaries="$summaries" '
    !inserted && /^---$/ && NR > 1 {
      print
      print ""
      print "<!-- collab:log-archived-summary:start -->"
      print summaries
      print "<!-- collab:log-archived-summary:end -->"
      print ""
      inserted = 1
      next
    }
    { print }
  ' "$new_log.body" > "$new_log"
  mv "$new_log" "$new_log.body"
fi

cp "$new_log.body" "$new_log"

# Restore original line endings.
if [[ $had_crlf -eq 1 ]]; then
  awk '{printf "%s\r\n", $0}' "$new_log" > "$LOG"
else
  cp "$new_log" "$LOG"
fi

rm -f "$tmp_norm" "$new_log" "$new_log.body"

bash "$HERE/collab-register.sh" "$ARCHIVE_FILE" >/dev/null 2>&1 || true
bash "$HERE/collab-register.sh" "$LOG" >/dev/null 2>&1 || true

echo "rotate: archived ${cut_idx} entries to $ARCHIVE_FILE; kept $KEEP recent entries in $LOG."
