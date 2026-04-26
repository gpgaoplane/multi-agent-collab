#!/usr/bin/env bash
# Audit INDEX against filesystem. Prints mismatches and exits non-zero if any.
# Scans under .claude/, .codex/, .gemini/, docs/agents/, .collab/ (excluding archive/).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-check: $INDEX missing" >&2
  exit 2
fi

# Surface UPGRADE_NOTES.md at the top so it's the first thing the agent sees.
if [[ -f .collab/UPGRADE_NOTES.md ]]; then
  echo "ATTENTION: .collab/UPGRADE_NOTES.md is present (unacked)."
  echo "  Read it, run the post-upgrade ritual (see PROTOCOL.md), then:"
  echo "    bash scripts/collab-init.sh --ack-upgrade"
  echo
fi

mismatches=0

# 1. INDEX references → filesystem check
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ ! -f "$path" ]]; then
    echo "MISSING (in INDEX, not on disk): $path"
    mismatches=$((mismatches + 1))
  fi
done < <(idx_list_paths "$INDEX")

# 2. Filesystem scan → INDEX check
scan_dirs=(.claude .codex .gemini docs/agents .collab)
for d in "${scan_dirs[@]}"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r -d '' path; do
    # Normalize: strip leading ./ (find may or may not prepend it depending on
    # the search-root form). Then skip archive/backup trees and .gitkeep.
    path="${path#./}"
    case "$path" in
      .collab/archive/*) continue ;;
      .collab/backup/*) continue ;;
      */.gitkeep) continue ;;
    esac
    if ! idx_get_row "$INDEX" "$path" | grep -q .; then
      # Only flag files with frontmatter (managed)
      if fm_has_frontmatter "$path"; then
        echo "ORPHAN (on disk, not in INDEX): $path"
        mismatches=$((mismatches + 1))
      fi
    fi
  done < <(find "$d" -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) -print0)
done

if [[ $mismatches -eq 0 ]]; then
  echo "OK: INDEX and filesystem aligned"
  audit_rc=0
else
  echo
  echo "$mismatches mismatch(es) found"
  audit_rc=1
fi

# --- Rotation threshold check (non-fatal) ---
check_rotation_threshold() {
  local cfg=".collab/config.yml"
  [[ -f "$cfg" ]] || return 0
  local threshold
  threshold=$(awk -F': *' '/^rotate_at_lines:/ { print $2; exit }' "$cfg")
  [[ -n "$threshold" && "$threshold" =~ ^[0-9]+$ ]] || return 0

  local warned=0
  for desc in .collab/agents.d/*.yml; do
    [[ -f "$desc" ]] || continue
    [[ "$(basename "$desc")" == _* ]] && continue
    local log
    log=$(awk -F': *' '/^log_path:/ { print $2 }' "$desc")
    [[ -f "$log" ]] || continue
    local count
    count=$(wc -l < "$log" | tr -d ' ')
    if [[ $count -gt $threshold ]]; then
      if [[ $warned -eq 0 ]]; then
        echo
        warned=1
      fi
      local agent
      agent=$(basename "$desc" .yml)
      echo "advisory: $log is $count lines (threshold $threshold). Run: ./scripts/collab-rotate-log.sh $agent"
    fi
  done
}
check_rotation_threshold || true

# --- Update advisory (non-fatal; skipped in CI / with update_channel:none) ---
check_for_update() {
  [[ "${CI:-}" == "true" ]] && return 0
  [[ -f .collab/config.yml ]] || return 0
  grep -qE '^update_channel:[[:space:]]*none' .collab/config.yml && return 0

  local cache=".collab/.update-cache"
  # Cache valid for 24h (applies to both successful and failed checks).
  if [[ -f "$cache" ]]; then
    local age=$(( $(date +%s) - $(stat -c%Y "$cache" 2>/dev/null || stat -f%m "$cache" 2>/dev/null || echo 0) ))
    [[ $age -lt 86400 ]] && return 0
  fi

  local url="${COLLAB_UPDATE_URL:-https://registry.npmjs.org/@gpgaoplane/multi-agent-collab}"
  local latest
  if [[ "$url" == file://* ]]; then
    latest=$(cat "${url#file://}" 2>/dev/null | grep -oE '"latest":"[^"]+"' | head -1 | cut -d'"' -f4)
  else
    latest=$(curl -sS --max-time 2 "$url" 2>/dev/null | grep -oE '"latest":"[^"]+"' | head -1 | cut -d'"' -f4)
  fi

  if [[ -z "$latest" ]]; then
    # Negative cache so 24h cooldown applies to failures too (no hammering on
    # flaky networks / offline).
    echo "check-failed: $(date +%s)" > "$cache"
    return 0
  fi

  echo "$latest" > "$cache"
  local installed=$(cat .collab/VERSION 2>/dev/null || echo "")
  if [[ -n "$installed" && "$latest" != "$installed" ]]; then
    echo
    echo "advisory: newer version $latest available (installed $installed). Upgrade with:"
    echo "  npx @gpgaoplane/multi-agent-collab@$latest init"
  fi
}

check_for_update || true

exit $audit_rc
