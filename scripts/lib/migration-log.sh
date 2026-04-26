#!/usr/bin/env bash
# Helper functions for migration scripts to emit structured BEFORE/AFTER lines.
# Sourced by scripts/migrations/*.sh.

# mlog_file_state <BEFORE|AFTER> <path>
# Prints a one-line summary of a file's state: line count + marker count, or
# "not present" if missing.
mlog_file_state() {
  local label="$1"
  local path="$2"
  if [[ ! -f "$path" ]]; then
    printf '[migration log] %-7s %s  (not present)\n' "$label:" "$path"
    return
  fi
  local lines markers
  lines=$(wc -l < "$path" | tr -d ' ')
  # grep -c prints "0" but exits 1 on no matches; `|| true` stops that from
  # propagating without appending another "0" to the captured output.
  markers=$(grep -cE '<!-- collab:[a-z-]+:start -->' "$path" 2>/dev/null || true)
  markers="${markers:-0}"
  printf '[migration log] %-7s %s  %d lines, %d marker block(s)\n' "$label:" "$path" "$lines" "$markers"
}

# mlog_action <description>
# Prints a one-line action note (e.g. "removed agent codex").
mlog_action() {
  printf '[migration log] %s\n' "$*"
}
