#!/usr/bin/env bash
# Assert the caller added a new `### Task Receipt` heading in the staged diff.
# Fallback: outside a git work tree, check that the file contains any receipt.
# Exit 0 on pass, 1 on fail, 2 on usage error.
set -euo pipefail

LOG="${1:-}"
[[ -f "$LOG" ]] || { echo "verify-receipt: log $LOG not found" >&2; exit 2; }

# Standalone mode: not in a git repo → check presence only.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  grep -q '^### Task Receipt' "$LOG"
  exit $?
fi

# In a git work tree: a new receipt must appear in the staged diff.
# ^\+### matches an ADDED line; ^-### (a removed line) must not count.
if git diff --cached -- "$LOG" | grep -qE '^\+### Task Receipt'; then
  exit 0
fi

exit 1
