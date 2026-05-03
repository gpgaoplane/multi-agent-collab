#!/usr/bin/env bash
# v0.4.2 (G5): two sequential upgrades without an ack in between must NOT
# silently overwrite the first UPGRADE_NOTES.md. The second upgrade should
# auto-archive the prior transient file before writing its own.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"
(cd "$TARGET" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.2.0" > "$TARGET/.collab/VERSION"

# --- First upgrade: writes UPGRADE_NOTES.md ---
out1=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "G5: first upgrade writes UPGRADE_NOTES.md"
[[ -f "$TARGET/.collab/UPGRADE_NOTES.md" ]] && ok || fail "first upgrade missing UPGRADE_NOTES"

start_test "G5: first UPGRADE_NOTES has status: transient"
grep -q '^status: transient$' "$TARGET/.collab/UPGRADE_NOTES.md" && ok || fail "first UPGRADE_NOTES not transient"

# Capture content of first notes for later byte-equivalence checks.
first_content=$(cat "$TARGET/.collab/UPGRADE_NOTES.md")
first_size=$(wc -c < "$TARGET/.collab/UPGRADE_NOTES.md" | tr -d ' ')

# --- Second upgrade WITHOUT ack: should auto-archive the first ---
# Pretend we're going from 0.3.0 to current shipped, since the first upgrade left us at shipped.
echo "0.3.0" > "$TARGET/.collab/VERSION"
sleep 1   # ensure HMS timestamp differs
out2=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "G5: second upgrade emits 'prior UPGRADE_NOTES was unacked' notice"
echo "$out2" | grep -q "prior UPGRADE_NOTES.md was unacked" && ok || fail "no auto-archive notice in stderr: $out2"

start_test "G5: second upgrade still writes a fresh UPGRADE_NOTES.md"
[[ -f "$TARGET/.collab/UPGRADE_NOTES.md" ]] && ok || fail "second UPGRADE_NOTES missing"

start_test "G5: prior UPGRADE_NOTES is preserved in archive (not lost)"
# The auto-archived file should match the first run's content.
auto_archived=$(ls "$TARGET/.collab/archive/UPGRADE_NOTES-"*.md 2>/dev/null | head -1)
[[ -n "$auto_archived" ]] && ok || fail "no auto-archived file present"

start_test "G5: archive content equals the first upgrade's notes"
archive_size=$(wc -c < "$auto_archived" | tr -d ' ')
[[ "$archive_size" == "$first_size" ]] && ok || fail "archive size $archive_size != first $first_size"

start_test "G5: live UPGRADE_NOTES.md content has changed (it's the second upgrade's)"
diff -q "$auto_archived" "$TARGET/.collab/UPGRADE_NOTES.md" >/dev/null 2>&1 && \
  fail "live notes equal archive — second upgrade silently overwrote!" || ok

# --- Schema check: archive filename uses from-to-HMS format ---
start_test "G5: archive filename follows UPGRADE_NOTES-<from>-to-<to>-<HMS>.md schema"
basename_archive=$(basename "$auto_archived")
echo "$basename_archive" | grep -qE '^UPGRADE_NOTES-[0-9]+\.[0-9]+\.[0-9]+-to-[0-9]+\.[0-9]+\.[0-9]+-[0-9]{14}(-[0-9]+)?\.md$' && ok || \
  fail "archive name does not match schema: $basename_archive"

# --- ack still works on the live copy after auto-archive ---
start_test "G5: --ack-upgrade after auto-archive produces a third archive"
out3=$( (cd "$TARGET" && bash scripts/collab-init.sh --ack-upgrade) 2>&1)
echo "$out3" | grep -q "archived UPGRADE_NOTES.md to" && ok || fail "--ack-upgrade after auto-archive failed: $out3"

start_test "G5: total archive count is at least 2 after the chain"
total=$(ls "$TARGET/.collab/archive/UPGRADE_NOTES-"*.md 2>/dev/null | wc -l | tr -d ' ')
[[ "$total" -ge "2" ]] && ok || fail "expected >= 2 archives, got $total"

report
