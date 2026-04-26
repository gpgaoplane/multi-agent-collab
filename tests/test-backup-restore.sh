#!/usr/bin/env bash
# Tests for M3: --backup (auto on upgrade) and --restore.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Setup: bootstrap a v0.3.0 install, commit clean baseline ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"

(cd "$TARGET" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.3.0" > "$TARGET/.collab/VERSION"
(cd "$TARGET" && git add -A && git commit -q -m "bootstrap at 0.3.0")

# --- Upgrade auto-creates a backup ---
start_test "upgrade auto-creates a backup directory"
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)
ls -d "$TARGET/.collab/backup/0.3.0-to-"*"-"* >/dev/null 2>&1 && ok || fail "no backup directory created: $(echo "$out" | tail -3)"

start_test "backup directory contains AI_AGENTS.md"
backup_dir=$(ls -1d "$TARGET/.collab/backup/"*/ | head -1)
[[ -f "$backup_dir/AI_AGENTS.md" ]] && ok || fail "backup missing AI_AGENTS.md"

start_test "backup directory contains AGENTS.md"
[[ -f "$backup_dir/AGENTS.md" ]] && ok || fail "backup missing AGENTS.md"

start_test "backup directory contains .collab/VERSION"
[[ -f "$backup_dir/.collab/VERSION" ]] && ok || fail "backup missing VERSION"

start_test "backup .collab/VERSION captures pre-upgrade version (0.3.0)"
ver=$(cat "$backup_dir/.collab/VERSION" | tr -d '[:space:]')
assert_eq "0.3.0" "$ver"

start_test "backup directory contains a RESTORE.md file"
[[ -f "$backup_dir/RESTORE.md" ]] && ok || fail "RESTORE.md missing"

start_test "backup VERSION captures pre-upgrade value while live VERSION advances"
# Synthetic bootstrap uses current-version templates for both before/after, so
# many file CONTENTS won't actually change. VERSION is the load-bearing
# differential: backup retains 0.3.0, live moves to shipped.
backup_ver=$(cat "$backup_dir/.collab/VERSION" | tr -d '[:space:]')
live_ver=$(cat "$TARGET/.collab/VERSION" | tr -d '[:space:]')
[[ "$backup_ver" == "0.3.0" && "$live_ver" != "0.3.0" ]] && ok || fail "expected backup=0.3.0, live!=0.3.0; got backup=$backup_ver live=$live_ver"

# --- --restore latest reverses ---
start_test "--restore latest restores AI_AGENTS.md to pre-upgrade state"
(cd "$TARGET" && bash scripts/collab-init.sh --restore latest) >/dev/null 2>&1
diff -q "$backup_dir/AI_AGENTS.md" "$TARGET/AI_AGENTS.md" >/dev/null 2>&1 && ok || fail "AI_AGENTS.md not restored"

start_test "--restore latest restores VERSION to 0.3.0"
ver_after=$(cat "$TARGET/.collab/VERSION" | tr -d '[:space:]')
assert_eq "0.3.0" "$ver_after"

# --- --no-backup skips ---
(cd "$TARGET" && git reset --hard HEAD -q && rm -rf .collab/backup .collab/UPGRADE_NOTES.md)
start_test "--no-backup skips backup creation"
(cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --no-backup) >/dev/null 2>&1
[[ ! -d "$TARGET/.collab/backup" ]] && ok || fail "backup created despite --no-backup"

# --- Multiple backups don't conflict ---
(cd "$TARGET" && git reset --hard HEAD -q && rm -rf .collab/backup .collab/UPGRADE_NOTES.md)
(cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) >/dev/null 2>&1
sleep 1   # ensure timestamp delta
(cd "$TARGET" && git reset --hard HEAD -q && rm -f .collab/UPGRADE_NOTES.md)
(cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) >/dev/null 2>&1

start_test "multiple upgrades produce distinct timestamped backup dirs"
n=$(ls -1d "$TARGET/.collab/backup/"*/ 2>/dev/null | wc -l | tr -d ' ')
[[ "$n" -ge 2 ]] && ok || fail "expected >= 2 backups, got $n"

# --- --restore <specific id> works ---
start_test "--restore <specific id> restores from named backup"
specific=$(ls -1 "$TARGET/.collab/backup/" | head -1)
(cd "$TARGET" && bash scripts/collab-init.sh --restore "$specific") >/dev/null 2>&1
ver_after=$(cat "$TARGET/.collab/VERSION" | tr -d '[:space:]')
assert_eq "0.3.0" "$ver_after"

# --- --restore on missing id errors ---
start_test "--restore <unknown id> errors non-zero"
out=$( (cd "$TARGET" && bash scripts/collab-init.sh --restore nonexistent-backup) 2>&1)
rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -q "no such backup" && ok || fail "expected error: rc=$rc out=$out"

report
