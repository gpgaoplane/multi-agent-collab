#!/usr/bin/env bash
# Prints current timestamp in ISO 8601 with timezone offset.
# Example: 2026-04-22T10:15:30-05:00
set -euo pipefail

# GNU date (Linux) supports %:z. BSD date (macOS) needs %z with manual insertion of colon.
# Windows Git Bash ships GNU date. Try %:z first; fall back to %z with sed.
# BSD date prints an unknown %:z as ":z", so check the whole offset shape
# (±HH:MM) rather than just looking for a colon.
if out=$(date +'%Y-%m-%dT%H:%M:%S%:z' 2>/dev/null) && [[ "$out" =~ [+-][0-9]{2}:[0-9]{2}$ ]]; then
  echo "$out"
  exit 0
fi

# Fallback: insert colon into ±HHMM → ±HH:MM
out=$(date +'%Y-%m-%dT%H:%M:%S%z')
echo "${out:0: -2}:${out: -2}"
