#!/usr/bin/env bash
# Prints current timestamp in ISO 8601 with timezone offset.
# Example: 2026-04-22T10:15:30-05:00
set -euo pipefail

# GNU date (Linux) supports %:z. BSD date (macOS) needs %z with manual insertion of colon.
# Windows Git Bash ships GNU date. Try %:z first; fall back to %z with sed.
if out=$(date +'%Y-%m-%dT%H:%M:%S%:z' 2>/dev/null) && [[ "$out" == *:* ]]; then
  # Guard: the timezone part (last 6 chars) must contain a colon to count as %:z success.
  tz="${out: -6}"
  if [[ "$tz" == *:* ]]; then
    echo "$out"
    exit 0
  fi
fi

# Fallback: insert colon into ±HHMM → ±HH:MM
out=$(date +'%Y-%m-%dT%H:%M:%S%z')
echo "${out:0: -2}:${out: -2}"
