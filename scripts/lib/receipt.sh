#!/usr/bin/env bash
# Receipt verification helper. Sourced by scripts/collab-verify-receipt.sh and
# inlined verbatim into the installed pre-commit hook by install_pre_commit_hook
# (so the hook has zero dependency on the skill source tree at commit time).
#
# verify_receipt <log-path>
# Returns:
#   0 — receipt detected per the active rule
#   1 — missing receipt
#   2 — usage error (caller should `exit $?`)
#
# Active rule:
#   - In a git work tree: the staged diff for <log-path> must contain a NEW
#     `### Task Receipt` heading (^+### Task Receipt).
#   - Outside a work tree (standalone mode): presence of any `### Task Receipt`
#     heading in the file is sufficient.

verify_receipt() {
  local log="${1:-}"
  [[ -f "$log" ]] || { echo "verify-receipt: log $log not found" >&2; return 2; }

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    grep -q '^### Task Receipt' "$log"
    return $?
  fi

  if git diff --cached -- "$log" | grep -qE '^\+### Task Receipt'; then
    return 0
  fi
  return 1
}
