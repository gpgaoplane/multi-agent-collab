#!/usr/bin/env bash
# Tests for M2: pre-migration cleanliness check.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Setup: simulate v0.3.0 install ready to upgrade ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"

(cd "$TARGET" && bash scripts/collab-init.sh) >/dev/null 2>&1
# Roll VERSION back to 0.3.0 so re-runs trigger upgrade mode, then commit so
# the working tree is clean (test cases can git-reset to this baseline).
echo "0.3.0" > "$TARGET/.collab/VERSION"
(cd "$TARGET" && git add -A && git commit -q -m "bootstrap at 0.3.0")

# --- Clean tree: upgrade proceeds ---
start_test "clean working tree allows upgrade to proceed"
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)
rc=$?
[[ $rc -eq 0 ]] && ok || fail "clean tree should allow upgrade: rc=$rc out=$out"

# Reset for next case.
(cd "$TARGET" && git reset --hard HEAD -q && rm -f .collab/UPGRADE_NOTES.md)

# --- Untracked-only files: allowed ---
echo "user note" > "$TARGET/my-untracked-note.txt"
start_test "untracked-only files do NOT block upgrade"
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)
rc=$?
[[ $rc -eq 0 ]] && ok || fail "untracked files should not block: rc=$rc out=$(echo "$out" | tail -5)"
rm -f "$TARGET/my-untracked-note.txt"

(cd "$TARGET" && git reset --hard HEAD -q && rm -f .collab/UPGRADE_NOTES.md)

# --- Modified tracked file: BLOCKS ---
echo "modified" >> "$TARGET/AI_AGENTS.md"
start_test "modified tracked file blocks upgrade"
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)
rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -q "tracked changes" && ok || fail "expected block: rc=$rc out=$(echo "$out" | tail -5)"

start_test "block message lists the dirty file"
echo "$out" | grep -q "AI_AGENTS.md" && ok || fail "block message did not name AI_AGENTS.md"

# --- --force-dirty overrides ---
start_test "--force-dirty allows upgrade despite dirty tree"
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --force-dirty) 2>&1)
rc=$?
[[ $rc -eq 0 ]] && ok || fail "--force-dirty should override: rc=$rc out=$(echo "$out" | tail -5)"

(cd "$TARGET" && git reset --hard HEAD -q && rm -f .collab/UPGRADE_NOTES.md)

# --- Staged file also blocks ---
echo "staged change" >> "$TARGET/AI_AGENTS.md"
(cd "$TARGET" && git add AI_AGENTS.md)
start_test "staged file also blocks upgrade"
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)
rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -q "tracked changes" && ok || fail "staged file should block: rc=$rc"

(cd "$TARGET" && git reset --hard HEAD -q && rm -f .collab/UPGRADE_NOTES.md)

# --- Re-init mode (same version) is NOT blocked by dirty tree ---
echo "uncommitted" >> "$TARGET/AI_AGENTS.md"
shipped=$(cat "$SKILL_ROOT/templates/collab/VERSION" | tr -d '[:space:]')
echo "$shipped" > "$TARGET/.collab/VERSION"
start_test "re-init (same version) is NOT blocked by dirty tree"
out=$( (cd "$TARGET" && bash scripts/collab-init.sh) 2>&1)
rc=$?
[[ $rc -eq 0 ]] && ok || fail "re-init should not check cleanliness: rc=$rc out=$(echo "$out" | tail -5)"

report
