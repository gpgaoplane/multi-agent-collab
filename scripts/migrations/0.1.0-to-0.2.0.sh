#!/usr/bin/env bash
# Migration: 0.1.0 → 0.2.0
# - Adds AGENTS.md front door (merge-aware).
# - No other target-repo state changes required.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$(cd "$HERE/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS/.." && pwd)"
TEMPLATES="$SKILL_ROOT/templates"

source "$SCRIPTS/lib/merge.sh"
source "$SCRIPTS/lib/migration-log.sh"

echo "Migrating v0.1.0 → v0.2.0..."

mlog_file_state "BEFORE" "AGENTS.md"
echo
echo ">>> Upgrade summary (v0.1.0 → v0.2.0):"
echo ">>>   - Adds AGENTS.md front door for cross-agent discovery."
echo ">>>   - No template content changes inside existing markers."
echo ">>>   - See CHANGELOG.md for full release notes."
echo

# Self-contained inject helper (kept separate from collab-init's copy so the
# migration can be re-run manually without sourcing the whole init script).
inject_agents_md_section() {
  local target="AGENTS.md"
  local template="$TEMPLATES/AGENTS.md"

  if [[ ! -f "$target" ]]; then
    cp "$template" "$target"
    echo "  created AGENTS.md"
    return
  fi

  if merge_has_section "$target" "agents-md"; then
    local new_content
    new_content=$(awk -v start="<!-- collab:agents-md:start -->" -v end="<!-- collab:agents-md:end -->" '
      $0 == start { in_sec = 1; next }
      $0 == end { in_sec = 0; next }
      in_sec { print }
    ' "$template")
    merge_replace_section "$target" "agents-md" "$new_content"
    echo "  refreshed managed AGENTS.md section"
  else
    {
      echo
      cat "$template"
    } >> "$target"
    echo "  appended managed AGENTS.md section to existing file"
  fi
}

inject_agents_md_section

mlog_file_state "AFTER" "AGENTS.md"

echo "Migration 0.1.0 → 0.2.0 complete."
