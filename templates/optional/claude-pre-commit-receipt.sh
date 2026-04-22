#!/usr/bin/env bash
# Optional pre-commit hook for Claude Code users.
# Asserts that any staged change to docs/agents/claude.md ends with a Task Receipt
# in the newest entry.
# Install via: cp templates/optional/claude-pre-commit-receipt.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
set -euo pipefail

LOG=docs/agents/claude.md

# Only enforce if the log is part of the staged changes.
if ! git diff --cached --name-only | grep -qx "$LOG"; then
  exit 0
fi

# Receipt regex: a `### Task Receipt` heading that is followed (within the next
# ~40 lines) by either a bullet starting with `-` or the phrase `Updates:`.
if awk '
  /^### Task Receipt/ { seen = 1; ctx = 40; next }
  seen && ctx-- > 0 {
    if (/^- / || /^Updates:/) { ok = 1; exit }
  }
  END { exit ok ? 0 : 1 }
' "$LOG"; then
  exit 0
fi

cat >&2 <<EOF
pre-commit: docs/agents/claude.md is being committed without a valid Task Receipt.

Add a '### Task Receipt' section to your latest entry listing which files this
task updated, OR use the trivial-task short form:

  ### Task Receipt
  Updates: none applicable (<short reason>)

See .collab/PROTOCOL.md for the full format.
EOF
exit 1
