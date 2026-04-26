#!/usr/bin/env bash
# Audit INDEX against filesystem. Prints mismatches and exits non-zero if any.
# Scans under .claude/, .codex/, .gemini/, docs/agents/, .collab/ (excluding archive/).
#
# Flags:
#   --stats    print per-agent stats (entry counts, log size, archive coverage)
#              instead of running the audit
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

STATS_MODE=0
case "${1:-}" in
  --stats) STATS_MODE=1 ;;
  -h|--help)
    sed -n '1,12p' "$0"
    exit 0
    ;;
esac

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-check: $INDEX missing" >&2
  exit 2
fi

# --stats mode: emit per-agent stats and exit. Doesn't run the audit.
if [[ $STATS_MODE -eq 1 ]]; then
  echo "collab-check stats"
  echo
  printf '%-12s  %-7s  %-9s  %-12s  %-10s\n' "agent" "entries" "log lines" "open handoff" "archives"
  printf '%-12s  %-7s  %-9s  %-12s  %-10s\n' "------------" "-------" "---------" "------------" "----------"
  for desc in .collab/agents.d/*.yml; do
    [[ -f "$desc" ]] || continue
    base=$(basename "$desc" .yml)
    [[ "$base" == _* ]] && continue
    log=$(awk -F': *' '/^log_path:/ { print $2 }' "$desc")
    entries=0
    log_lines=0
    open_handoffs=0
    if [[ -f "$log" ]]; then
      entries=$(grep -cE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$log" 2>/dev/null || true)
      log_lines=$(wc -l < "$log" | tr -d ' ')
      # Open handoff = a handoff:start marker whose status line is "open".
      open_handoffs=$(awk '
        /<!-- collab:handoff:start id=/ { in_blk=1; st="" }
        in_blk && /^- \*\*status:\*\*/ { st=$0 }
        /<!-- collab:handoff:end -->/ { if (st ~ / open$/) c++; in_blk=0 }
        END { print c+0 }
      ' "$log")
    fi
    # ls exits 1 when the glob has no matches; pipefail propagates that and
    # set -e would terminate the loop. `|| true` absorbs it.
    archives=$(ls -1 ".collab/archive/agents/${base}-"*.md 2>/dev/null | wc -l | tr -d ' ' || true)
    archives="${archives:-0}"
    printf '%-12s  %-7s  %-9s  %-12s  %-10s\n' "$base" "$entries" "$log_lines" "$open_handoffs" "$archives"
  done

  # Total managed file count from INDEX.
  total=$(awk -F'|' '/^\| [^-]/ && !/^\| path/ { c++ } END { print c+0 }' "$INDEX")
  echo
  echo "INDEX entries (total managed files): $total"
  exit 0
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
