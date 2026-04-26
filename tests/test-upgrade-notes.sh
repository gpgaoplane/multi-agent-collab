#!/usr/bin/env bash
# Tests for Group F: upgrade communication.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Setup: simulate v0.2.0 install, run upgrade chain to shipped ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"

(cd "$TARGET" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.2.0" > "$TARGET/.collab/VERSION"

# Run upgrade. COLLAB_MIGRATE_NONINTERACTIVE so 0.3.0→0.4.0 doesn't try to read /dev/tty.
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "migration emits >>> Upgrade summary block to stdout"
echo "$out" | grep -q ">>> Upgrade summary" && ok || fail "no upgrade summary in stdout"

start_test "0.2.0->0.3.0 summary mentions config.yml"
echo "$out" | grep -q "config.yml" && ok || fail "config.yml summary missing"

start_test "0.3.0->0.4.0 summary mentions calling-agent-only"
echo "$out" | grep -q "calling agent" && ok || fail "calling-agent summary missing"

start_test "upgrade writes .collab/UPGRADE_NOTES.md"
assert_file_exists "$TARGET/.collab/UPGRADE_NOTES.md"

start_test "UPGRADE_NOTES.md has status: transient frontmatter"
grep -q '^status: transient$' "$TARGET/.collab/UPGRADE_NOTES.md" && ok || fail "UPGRADE_NOTES.md missing transient status"

start_test "UPGRADE_NOTES.md captures the upgrade summaries"
grep -q ">>> Upgrade summary" "$TARGET/.collab/UPGRADE_NOTES.md" && ok || fail "UPGRADE_NOTES.md lacks summaries"

start_test "UPGRADE_NOTES.md includes post-upgrade ritual instructions"
grep -q "Post-upgrade ritual" "$TARGET/.collab/UPGRADE_NOTES.md" && ok || fail "ritual instructions missing"

start_test "UPGRADE_NOTES.md is registered in INDEX"
grep -q "UPGRADE_NOTES.md" "$TARGET/.collab/INDEX.md" && ok || fail "UPGRADE_NOTES.md not registered"

start_test "collab-check surfaces UPGRADE_NOTES.md at top of output"
out2=$( (cd "$TARGET" && bash scripts/collab-check.sh) 2>&1)
echo "$out2" | head -3 | grep -q "UPGRADE_NOTES.md is present" && ok || fail "collab-check did not surface notes: $(echo "$out2" | head -3)"

start_test "collab-check advises --ack-upgrade"
echo "$out2" | grep -q "ack-upgrade" && ok || fail "no ack-upgrade hint"

# --- ack-upgrade archives the file ---
start_test "--ack-upgrade archives UPGRADE_NOTES.md"
out3=$( (cd "$TARGET" && bash scripts/collab-init.sh --ack-upgrade) 2>&1)
[[ ! -f "$TARGET/.collab/UPGRADE_NOTES.md" ]] && ok || fail "UPGRADE_NOTES.md still present after ack"

start_test "ack-upgrade moves file under .collab/archive/"
ls "$TARGET/.collab/archive/UPGRADE_NOTES-"*.md >/dev/null 2>&1 && ok || fail "archive copy missing"

start_test "ack-upgrade is idempotent (no-op when no notes file)"
out4=$( (cd "$TARGET" && bash scripts/collab-init.sh --ack-upgrade) 2>&1)
echo "$out4" | grep -q "nothing to do" && ok || fail "expected idempotent no-op: $out4"

# --- Concurrent ack: simulate by re-creating UPGRADE_NOTES.md and acking when archived already exists ---
start_test "ack-upgrade handles already-archived case (no overwrite)"
echo "test" > "$TARGET/.collab/UPGRADE_NOTES.md"
out5=$( (cd "$TARGET" && bash scripts/collab-init.sh --ack-upgrade) 2>&1)
echo "$out5" | grep -q "already archived" && [[ ! -f "$TARGET/.collab/UPGRADE_NOTES.md" ]] && ok || fail "concurrent ack did not handle existing archive: $out5"

# --- Post-upgrade ritual is documented in PROTOCOL.md ---
start_test "PROTOCOL.md documents Post-upgrade ritual"
grep -q "Post-upgrade ritual" "$SKILL_ROOT/templates/collab/PROTOCOL.md" && ok || fail "ritual not in PROTOCOL.md"

start_test "PROTOCOL.md ritual references --ack-upgrade"
grep -q "ack-upgrade" "$SKILL_ROOT/templates/collab/PROTOCOL.md" && ok || fail "ritual missing ack-upgrade reference"

report
