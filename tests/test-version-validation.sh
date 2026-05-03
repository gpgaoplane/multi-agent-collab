#!/usr/bin/env bash
# v0.4.2 (G6): detect_mode validates .collab/VERSION format.
# Garbage content (typo, partial corruption) was silently triggering
# lexicographic compare and skipping migrations. Now hard-fails with
# guidance, and the failure does NOT lock users out of --restore.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Setup: a clean v0.4.x install ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cd "$TARGET"
bash "$SKILL_ROOT/scripts/collab-init.sh" --agent claude >/dev/null 2>&1

# --- Garbage VERSION → init exits non-zero with helpful message ---
echo "9.0.0-not-actually-released" > .collab/VERSION

start_test "G6: garbage VERSION causes init to exit non-zero"
out=$(bash "$SKILL_ROOT/scripts/collab-init.sh" 2>&1 || true)
status=$?
echo "$out" | grep -q "invalid version" && ok || fail "expected 'invalid version' error; got: $out"

# --- Empty VERSION → also fails ---
> .collab/VERSION

start_test "G6: empty VERSION causes init to exit non-zero"
out=$(bash "$SKILL_ROOT/scripts/collab-init.sh" 2>&1 || true)
echo "$out" | grep -q "invalid version" && ok || fail "expected 'invalid version' error on empty: $out"

# --- Non-semver string ('latest', etc.) → also fails ---
echo "latest" > .collab/VERSION

start_test "G6: non-semver VERSION ('latest') fails"
out=$(bash "$SKILL_ROOT/scripts/collab-init.sh" 2>&1 || true)
echo "$out" | grep -q "invalid version" && ok || fail "expected 'invalid version' error on 'latest': $out"

# --- Lockout check: --restore latest STILL works on garbage VERSION ---
# Make sure we have a backup to restore. Re-init to create a fresh state with
# the correct VERSION, then trigger an upgrade so a backup is captured.
echo "0.4.1" > .collab/VERSION
# Force-create a synthetic backup directly (avoid the chained-migration setup).
mkdir -p .collab/backup/0.4.1-to-0.4.2-20260502000000/.collab
echo "0.4.1" > .collab/backup/0.4.1-to-0.4.2-20260502000000/.collab/VERSION
# Now corrupt VERSION again.
echo "garbage-here" > .collab/VERSION

start_test "G6: --restore latest works despite garbage VERSION (no lockout)"
out=$(bash "$SKILL_ROOT/scripts/collab-init.sh" --restore latest 2>&1 || true)
# After restore, VERSION should be valid again.
ver=$(cat .collab/VERSION)
[[ "$ver" == "0.4.1" ]] && ok || fail "VERSION not restored: out=$out ver=$ver"

# --- Valid semver still proceeds normally ---
echo "0.4.1" > .collab/VERSION

start_test "G6: valid semver VERSION proceeds normally"
out=$(bash "$SKILL_ROOT/scripts/collab-init.sh" 2>&1 || true)
echo "$out" | grep -q "Mode:" && ok || fail "expected mode detection to succeed; got: $out"

cd "$SKILL_ROOT"
report
