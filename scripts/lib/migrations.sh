#!/usr/bin/env bash
# Migration sentinel helpers — moved out of collab-init.sh in v0.4.3 (X1b)
# so that scripts/collab-update.sh can source them without dragging in
# init's top-level dispatch.
#
# Sentinels live at .collab/.migrations/<from>-to-<to>.applied with content:
#   applied-at: <ISO-8601>
#   script-sha: <hex-sha256 of the migration script body, or no-sha-available>
#
# Required environment when sourcing:
#   $HERE — directory containing the calling script (used to resolve
#           collab-now.sh and collab_sha256). Set by callers to "$(cd
#           "$(dirname "$0")" && pwd)".
#
# Required dependencies (sourced before this lib):
#   scripts/lib/sha.sh   — provides collab_sha256
#   scripts/lib/semver.sh — provides version_le
#
# Provides:
#   ensure_migration_dir              — mkdir + seed README.md if absent
#   write_migration_sentinel <f> <t> <script-path>
#   is_migration_applied <f> <t> <script-path>
#   backfill_legacy_sentinels <installed-version>

ensure_migration_dir() {
  local dir=".collab/.migrations"
  [[ -d "$dir" ]] && return 0
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  mkdir -p "$dir"
  cat > "$dir/README.md" <<'EOF'
---
status: managed
type: framework-state
owner: shared
last-updated: 2026-05-02T00:00:00-00:00
read-if: "you are inspecting which migrations have already been applied"
skip-if: "always — this is framework runtime state, not user content"
---

# Migration sentinels

Each `<from>-to-<to>.applied` file records that the corresponding migration
script in `scripts/migrations/` has already run against this install. The
chain runner in `collab-init.sh` consults these sentinels to make repeated
upgrades safe (re-running an already-applied migration is a no-op) and
to allow a migration to be re-triggered if the shipped script body has
changed (SHA mismatch).

Do not edit by hand. To force re-run of a specific migration, delete its
sentinel file and re-run `collab-init`.
EOF
}

# write_migration_sentinel <from> <to> <script-path>
write_migration_sentinel() {
  local from="$1" to="$2" script_path="$3"
  ensure_migration_dir
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  local sentinel=".collab/.migrations/${from}-to-${to}.applied"
  local sha
  if [[ -f "$script_path" ]]; then
    sha=$(collab_sha256 "$script_path")
  else
    sha="no-sha-available"
  fi
  {
    printf 'applied-at: %s\n' "$(bash "$HERE/collab-now.sh")"
    printf 'script-sha: %s\n' "$sha"
  } > "$sentinel"
}

# is_migration_applied <from> <to> <script-path>
# Returns 0 (already applied; safe to skip) when the sentinel exists AND
# the recorded SHA matches the current script. SHA mismatch (script body
# changed) returns 1 so the migration re-runs. Missing sentinel returns 1.
# Special case: if either side is "no-sha-available" (minimal shells without
# any SHA tool), we DEFAULT to "skip on sentinel presence" — the user's
# environment can't verify drift, so we err on the side of idempotence.
is_migration_applied() {
  local from="$1" to="$2" script_path="$3"
  local sentinel=".collab/.migrations/${from}-to-${to}.applied"
  [[ -f "$sentinel" ]] || return 1
  local recorded_sha current_sha
  recorded_sha=$(awk -F': *' '/^script-sha:/ { print $2; exit }' "$sentinel")
  if [[ -f "$script_path" ]]; then
    current_sha=$(collab_sha256 "$script_path")
  else
    current_sha="no-sha-available"
  fi
  if [[ "$recorded_sha" == "no-sha-available" || "$current_sha" == "no-sha-available" ]]; then
    return 0   # skip (no SHA available, default to idempotence)
  fi
  [[ "$recorded_sha" == "$current_sha" ]]
}

# backfill_legacy_sentinels <installed>
# On the first v0.4.2 upgrade for an existing v0.4.x install, the
# .collab/.migrations/ directory doesn't exist yet. Pre-fill sentinels for
# every legacy migration whose dst <= installed, so the loop below
# correctly skips them instead of trying to re-run.
backfill_legacy_sentinels() {
  local installed="$1"
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  local known_dst=("0.2.0" "0.3.0" "0.4.0" "0.4.1")
  local dst
  for dst in "${known_dst[@]}"; do
    if version_le "$dst" "$installed"; then
      # Find the matching script (dst is unique among known migrations).
      local script
      for script in "$HERE/migrations/"*-to-"$dst".sh; do
        [[ -f "$script" ]] || continue
        local base src
        base=$(basename "$script" .sh)
        src="${base%-to-*}"
        local sentinel=".collab/.migrations/${src}-to-${dst}.applied"
        if [[ ! -f "$sentinel" ]]; then
          write_migration_sentinel "$src" "$dst" "$script"
        fi
      done
    fi
  done
}
