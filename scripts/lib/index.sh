#!/usr/bin/env bash
# INDEX.md manipulation helpers.
# The INDEX body between <!-- collab:index:start --> and <!-- collab:index:end -->
# is a markdown table of rows: path | type | owner | status | last-updated

IDX_START_MARKER="<!-- collab:index:start -->"
IDX_END_MARKER="<!-- collab:index:end -->"

# idx_get_row <index-file> <path>
# Echoes the full pipe-delimited row if present, empty otherwise.
idx_get_row() {
  local file="$1"
  local path="$2"
  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" -v path="$path" '
    $0 == start { in_table = 1; next }
    $0 == end { in_table = 0; next }
    in_table {
      # Skip header and separator rows.
      if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) next
      # Match rows whose first column equals path (trimmed).
      line = $0
      # Strip leading/trailing pipe+space
      n = split(line, parts, /[ \t]*\|[ \t]*/)
      # parts[1] is empty (before first |), parts[2] is path column
      if (n >= 2 && parts[2] == path) { print line; exit }
    }
  ' "$file"
}

# idx_list_paths <index-file>
# Prints each registered path, one per line.
idx_list_paths() {
  local file="$1"
  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" '
    $0 == start { in_table = 1; next }
    $0 == end { in_table = 0; next }
    in_table {
      if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) next
      n = split($0, parts, /[ \t]*\|[ \t]*/)
      if (n >= 2 && parts[2] != "") print parts[2]
    }
  ' "$file"
}

# idx_upsert <index-file> <path> <type> <owner> <status> <last-updated>
# Updates existing row for <path>, or appends a new row if absent.
idx_upsert() {
  local file="$1"
  local path="$2"
  local type="$3"
  local owner="$4"
  local status="$5"
  local last_updated="$6"
  local new_row="| $path | $type | $owner | $status | $last_updated |"

  local tmp
  tmp=$(mktemp)

  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" \
      -v path="$path" -v new_row="$new_row" '
    {
      if ($0 == start) { in_table = 1; print; next }
      if ($0 == end) {
        if (in_table && !replaced) { print new_row; replaced = 1 }
        in_table = 0
        print
        next
      }
      if (in_table) {
        if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) { print; next }
        n = split($0, parts, /[ \t]*\|[ \t]*/)
        if (n >= 2 && parts[2] == path) {
          print new_row
          replaced = 1
          next
        }
      }
      print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}

# idx_remove <index-file> <path>
idx_remove() {
  local file="$1"
  local path="$2"
  local tmp
  tmp=$(mktemp)

  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" -v path="$path" '
    {
      if ($0 == start) { in_table = 1; print; next }
      if ($0 == end) { in_table = 0; print; next }
      if (in_table) {
        if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) { print; next }
        n = split($0, parts, /[ \t]*\|[ \t]*/)
        if (n >= 2 && parts[2] == path) next
      }
      print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}
