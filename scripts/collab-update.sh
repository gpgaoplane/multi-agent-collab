#!/usr/bin/env bash
# collab-update.sh — single-trigger upgrade entry point (v0.4.3+).
#
# Wraps init's existing upgrade mode with a pre-flight version check,
# interactive confirmation prompt, and post-flight ack reminder. ZERO new
# preservation mechanisms — every safety layer (cleanliness check, auto-backup,
# migration sentinels, marker-guided merge, UPGRADE_NOTES auto-archive,
# byte-equivalent restore) is inherited from collab-init.sh.
#
# One genuinely new behavior: --rollback cleans up .collab/.migrations/
# sentinels for migrations being rolled back. Without that cleanup, the next
# update would silently skip migrations because sentinels say "applied" while
# VERSION says pre-upgrade.
#
# Modes (mutually exclusive):
#   update                Pre-flight + confirm + apply + post-flight reminder.
#   update --check        Pure check (cache-only). No state changes.
#   update --ack          Archive UPGRADE_NOTES.md + run collab-check.
#   update --rollback     Restore latest backup + clean stale sentinels.
#
# Modifier flags:
#   --yes / -y            Skip confirmation prompts (required for non-tty).
#   --diff-first          Run --diff preview, confirm, then apply.
#   --no-backup           Pass through to init (skip auto-backup).
#   --force-dirty         Pass through (allow upgrade on dirty git tree).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
TEMPLATES="$SKILL_ROOT/templates"

source "$HERE/lib/sha.sh"
source "$HERE/lib/semver.sh"
source "$HERE/lib/migrations.sh"

usage() {
  cat <<'EOF'
Usage: collab-update.sh [mode] [flags]

Modes (mutually exclusive):
  (none, default)         Run upgrade flow: pre-flight check + confirm +
                          apply + post-flight reminder.
  --check                 Print installed and latest versions; no state
                          changes. Reads .collab/.update-cache only (does
                          not hit npm). Run 'collab-check' to refresh cache.
  --ack                   Archive .collab/UPGRADE_NOTES.md after the
                          post-upgrade ritual. Auto-prunes old backups.
  --rollback              Restore the latest backup + clean stale migration
                          sentinels for rolled-back migrations.

Modifier flags:
  --yes, -y               Skip the confirmation prompt (required for
                          non-tty contexts: CI, scripts).
  --diff-first            Show a unified diff of pending changes; confirm;
                          then apply. ~2x runtime; opt-in.
  --no-backup             Skip auto-backup before applying. NOT recommended.
  --force-dirty           Allow upgrade even when the git working tree is dirty.

Other:
  --help, -h              Show this message.
EOF
}

# --- Argparse ---

MODE="default"
YES=0
DIFF_FIRST=0
NO_BACKUP=0
FORCE_DIRTY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      [[ "$MODE" == "default" ]] || { echo "update: --check is mutually exclusive with --ack/--rollback" >&2; exit 2; }
      MODE="check"; shift ;;
    --ack)
      [[ "$MODE" == "default" ]] || { echo "update: --ack is mutually exclusive with --check/--rollback" >&2; exit 2; }
      MODE="ack"; shift ;;
    --rollback)
      [[ "$MODE" == "default" ]] || { echo "update: --rollback is mutually exclusive with --check/--ack" >&2; exit 2; }
      MODE="rollback"; shift ;;
    --yes|-y) YES=1; shift ;;
    --diff-first) DIFF_FIRST=1; shift ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --force-dirty) FORCE_DIRTY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "update: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- Helpers ---

# Prompt for confirmation. Returns 0 on accept, 1 on decline.
# Hard-fails when stdin is closed/empty without --yes (CI scenario).
# Reads from stdin whether tty or pipe — supports both interactive and
# `printf 'y\n' | update` test patterns. The right signal for "no human
# present" is EOF on read, not tty-detection (which would block pipes).
prompt_confirm() {
  local msg="${1:-Continue?}"
  local reply
  if ! read -r -p "$msg [Y/n]: " reply; then
    echo >&2
    echo "update: confirmation required (EOF on stdin); pass --yes for non-interactive contexts" >&2
    exit 2
  fi
  case "${reply:-y}" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# Read installed version + validate format (semver X.Y.Z).
# Hard-fails if .collab/VERSION missing or contains garbage.
read_installed_version() {
  if [[ ! -f .collab/VERSION ]]; then
    echo "update: this repo is not bootstrapped. Run 'init' first." >&2
    exit 2
  fi
  local installed
  installed="$(cat .collab/VERSION | tr -d '[:space:]')"
  if [[ ! "$installed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "update: .collab/VERSION contains invalid version: '$installed'" >&2
    echo "Expected semver X.Y.Z. Either restore from a backup with --rollback," >&2
    echo "or fix .collab/VERSION manually." >&2
    exit 2
  fi
  printf '%s' "$installed"
}

# Read shipped version from the local templates/ directory.
read_shipped_version() {
  cat "$TEMPLATES/collab/VERSION" | tr -d '[:space:]'
}

# Read cached "latest" from the update-advisory cache (24h TTL).
# Format: bare version string OR "check-failed: <epoch>" (negative cache).
# Echoes the version string, or empty if cache missing/failed/garbage.
read_cached_latest() {
  local cache=".collab/.update-cache"
  if [[ ! -f "$cache" ]]; then
    echo ""
    return
  fi
  local content
  content="$(cat "$cache" | tr -d '[:space:]')"
  if [[ "$content" == check-failed:* ]]; then
    echo ""
    return
  fi
  if [[ "$content" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$content"
  else
    echo ""
  fi
}

# Compute migrations that will RUN (sentinel-filtered) for an upgrade from
# $installed to $shipped. Echoes one "src→dst" per line. Empty output means
# all migrations are already applied per sentinels (re-init only).
compute_pending_migrations() {
  local installed="$1" shipped="$2"
  local from="$installed"
  local script base src dst
  for script in "$HERE/migrations/"*-to-*.sh; do
    [[ -f "$script" ]] || continue
    base=$(basename "$script" .sh)
    src="${base%-to-*}"
    dst="${base##*-to-}"
    [[ "$src" == "$from" ]] || continue
    version_le "$dst" "$shipped" || continue
    if is_migration_applied "$src" "$dst" "$script"; then
      from="$dst"
      continue
    fi
    echo "${src}→${dst}"
    from="$dst"
  done
}

# --- Mode dispatch ---

case "$MODE" in
  check)
    installed=$(read_installed_version)
    shipped=$(read_shipped_version)
    cached_latest=$(read_cached_latest)

    echo "Multi-agent-collab framework"
    echo "  Installed: $installed"
    if [[ -n "$cached_latest" ]]; then
      echo "  Latest:    $cached_latest (from cache)"
    elif [[ -f .collab/.update-cache ]]; then
      echo "  Latest:    unknown (last check failed; run 'bash $SKILL_ROOT/scripts/collab-check.sh' to refresh)"
    else
      echo "  Latest:    unknown (run 'bash $SKILL_ROOT/scripts/collab-check.sh' to refresh)"
    fi
    echo "  Shipped (this skill source): $shipped"

    if version_eq "$installed" "$shipped"; then
      echo "Already up to date."
    elif version_le "$installed" "$shipped"; then
      echo "Upgrade available. Run 'update' to apply."
    else
      echo "Installed version is newer than shipped. Nothing to do."
    fi
    exit 0
    ;;

  ack)
    bash "$HERE/collab-init.sh" --ack-upgrade
    echo
    echo "Final state:"
    bash "$HERE/collab-check.sh" || true
    exit 0
    ;;

  rollback)
    if [[ ! -d .collab/backup ]] || [[ -z "$(ls -A .collab/backup 2>/dev/null)" ]]; then
      echo "update: no backup to restore from; nothing was changed."
      exit 0
    fi

    # Find latest backup directory (by mtime) and parse <from> from its name.
    latest_backup=$(ls -1t .collab/backup 2>/dev/null | head -1)
    if [[ -z "$latest_backup" ]]; then
      echo "update: no backup to restore from; nothing was changed."
      exit 0
    fi

    # Backup directory name format: <from>-to-<to>-<YYYYMMDDHHMMSS>
    # Parse <from> by stripping the "-to-..." suffix.
    rolled_from="${latest_backup%%-to-*}"

    if [[ ! "$rolled_from" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "update: latest backup name '$latest_backup' doesn't match expected schema; refusing to rollback." >&2
      echo "Use 'bash $HERE/collab-init.sh --restore <id>' directly to override." >&2
      exit 2
    fi

    echo "Rolling back to $rolled_from from backup $latest_backup..."
    bash "$HERE/collab-init.sh" --restore latest

    # Sentinel cleanup: delete sentinels for migrations whose dst > rolled_from.
    # Without this, the next 'update' silently skips those migrations because
    # sentinels say "applied" while .collab/VERSION reverted to pre-upgrade.
    pruned=0
    if [[ -d .collab/.migrations ]]; then
      for sentinel in .collab/.migrations/*.applied; do
        [[ -f "$sentinel" ]] || continue
        sentinel_name=$(basename "$sentinel" .applied)
        sentinel_dst="${sentinel_name##*-to-}"
        if ! version_le "$sentinel_dst" "$rolled_from"; then
          rm -f "$sentinel"
          pruned=$((pruned + 1))
        fi
      done
    fi

    echo "Rolled back to $rolled_from. Removed $pruned stale sentinel(s)."
    exit 0
    ;;

  default)
    installed=$(read_installed_version)
    shipped=$(read_shipped_version)

    # Already current?
    if version_eq "$installed" "$shipped"; then
      echo "Already up to date ($installed)."
      exit 0
    fi

    # Newer than shipped (dev-clone scenario)?
    if ! version_le "$installed" "$shipped"; then
      echo "Installed version $installed is newer than shipped $shipped. Nothing to do."
      exit 0
    fi

    # Compute pending migrations (sentinel-filtered).
    mapfile -t pending < <(compute_pending_migrations "$installed" "$shipped")
    pending_count=${#pending[@]}

    # Display summary.
    echo "Multi-agent-collab framework update"
    echo "  Installed: $installed"
    echo "  Latest:    $shipped"
    if [[ $pending_count -eq 0 ]]; then
      echo "  Migrations to run: 0 (all already-applied per sentinels)"
      echo "  Will run re-init only (refresh managed sections)."
    else
      printf '  Migrations to run: %d (' "$pending_count"
      printf '%s' "${pending[0]}"
      for ((i = 1; i < pending_count; i++)); do
        printf ', %s' "${pending[i]}"
      done
      printf ')\n'
    fi
    if [[ $NO_BACKUP -eq 0 ]]; then
      echo "  Auto-backup will run before any changes."
    else
      echo "  Auto-backup DISABLED (--no-backup)."
    fi
    echo

    # --diff-first: show diff first; pre-flight prompt suppressed.
    if [[ $DIFF_FIRST -eq 1 ]]; then
      echo "Running --diff to preview changes (this will not modify the repo)..."
      echo
      diff_args=(--diff)
      [[ $FORCE_DIRTY -eq 1 ]] && diff_args+=(--force-dirty)
      bash "$HERE/collab-init.sh" "${diff_args[@]}"
      echo
      if [[ $YES -ne 1 ]]; then
        if ! prompt_confirm "Apply these changes?"; then
          echo "Declined. No changes applied."
          exit 0
        fi
      fi
    else
      # Default: prompt-then-apply.
      if [[ $YES -ne 1 ]]; then
        if ! prompt_confirm "Continue?"; then
          echo "Declined. No changes applied."
          exit 0
        fi
      fi
    fi

    # Apply.
    apply_args=()
    [[ $NO_BACKUP -eq 1 ]] && apply_args+=(--no-backup)
    [[ $FORCE_DIRTY -eq 1 ]] && apply_args+=(--force-dirty)
    bash "$HERE/collab-init.sh" "${apply_args[@]}"

    # Post-flight.
    echo
    if [[ -f .collab/UPGRADE_NOTES.md ]]; then
      echo "Upgrade complete."
      echo "  1. Read .collab/UPGRADE_NOTES.md and run the post-upgrade ritual."
      echo "  2. Once done, run: bash $HERE/collab-update.sh --ack"
    else
      echo "Re-init complete. No upgrade notes generated."
    fi
    exit 0
    ;;
esac
