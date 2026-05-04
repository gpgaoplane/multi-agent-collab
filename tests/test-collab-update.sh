#!/usr/bin/env bash
# v0.4.3 (G1): tests for the new `update` subcommand.
#
# Coverage matrix per plan §3.3:
# - Mode dispatch: default, --check, --ack, --rollback (mutually exclusive)
# - Modifiers: --yes, --diff-first, --no-backup, --force-dirty
# - Confirmation prompt branches: y/Y/yes/empty/n/N/no/garbage/EOF
# - Edge cases: bootstrap-check, garbage VERSION, cache-missing, cache-failed
# - LOAD-BEARING: rollback then re-upgrade — verifies sentinel cleanup
#   actually un-skips migrations on the next chain run.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
UPDATE="$SKILL_ROOT/scripts/collab-update.sh"

# Helper: bootstrap a v0.4.0 install in a fresh tmp repo. Sets it up so
# `update` would have a real upgrade path (4 migrations: .0→.1, .1→.2, .2→.3).
make_v040_repo() {
  local repo
  repo=$(make_tmp_repo)
  cp -R "$SKILL_ROOT/scripts" "$repo/scripts"
  cp -R "$SKILL_ROOT/templates" "$repo/templates"
  (cd "$repo" && bash scripts/collab-init.sh) >/dev/null 2>&1
  echo "0.4.0" > "$repo/.collab/VERSION"
  echo "$repo"
}

# Helper: bootstrap at the SHIPPED version (already-current).
make_current_repo() {
  local repo
  repo=$(make_tmp_repo)
  cp -R "$SKILL_ROOT/scripts" "$repo/scripts"
  cp -R "$SKILL_ROOT/templates" "$repo/templates"
  (cd "$repo" && bash scripts/collab-init.sh) >/dev/null 2>&1
  echo "$repo"
}

trap '
  rm -rf "${TARGET:-}" "${TARGET2:-}" "${TARGET3:-}" "${TARGET4:-}" \
         "${TARGET5:-}" "${TARGET6:-}" "${TARGET7:-}" "${TARGET8:-}" \
         "${TARGET9:-}" "${TARGET10:-}" "${TARGET11:-}" "${TARGET12:-}"
' EXIT

# ============================================================
# --check mode
# ============================================================

# 1. --check on already-current install
TARGET=$(make_current_repo)
start_test "G1: --check on already-current install"
out=$( (cd "$TARGET" && bash "$UPDATE" --check) 2>&1)
echo "$out" | grep -q "Already up to date" && ok || fail "expected 'Already up to date'; got: $out"

# 2. --check shows installed and shipped versions
start_test "G1: --check displays installed AND shipped versions"
echo "$out" | grep -q "Installed:" && echo "$out" | grep -q "Shipped" && ok || fail "expected version lines: $out"

# 3. --check on out-of-date install
TARGET2=$(make_v040_repo)
start_test "G1: --check on v0.4.0 install reports upgrade available"
out=$( (cd "$TARGET2" && bash "$UPDATE" --check) 2>&1)
echo "$out" | grep -q "Installed: 0.4.0" && echo "$out" | grep -q "Upgrade available" && ok || \
  fail "expected upgrade-available message; got: $out"

# 4. --check makes NO state changes
start_test "G1: --check leaves .collab/VERSION unchanged"
ver=$(cat "$TARGET2/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "0.4.0" ]] && ok || fail "VERSION changed to $ver"

# 5. --check with cache missing
start_test "G1: --check with cache missing prints 'unknown'"
rm -f "$TARGET2/.collab/.update-cache"
out=$( (cd "$TARGET2" && bash "$UPDATE" --check) 2>&1)
echo "$out" | grep -q "Latest:    unknown" && ok || fail "expected 'unknown'; got: $out"

# 6. --check with check-failed cache
start_test "G1: --check with check-failed cache prints 'unknown' (last check failed)"
echo "check-failed: 1234567890" > "$TARGET2/.collab/.update-cache"
out=$( (cd "$TARGET2" && bash "$UPDATE" --check) 2>&1)
echo "$out" | grep -q "last check failed" && ok || fail "expected 'last check failed'; got: $out"

# 7. --check with valid cached version
start_test "G1: --check with valid cached version prints it"
echo "0.4.3" > "$TARGET2/.collab/.update-cache"
out=$( (cd "$TARGET2" && bash "$UPDATE" --check) 2>&1)
echo "$out" | grep -q "Latest:    0.4.3 (from cache)" && ok || fail "expected cached latest; got: $out"

# 8. --check on non-bootstrapped repo
TARGET3=$(make_tmp_repo)
start_test "G1: --check on non-bootstrapped repo errors"
out=$( (cd "$TARGET3" && bash "$UPDATE" --check) 2>&1 || true)
echo "$out" | grep -q "not bootstrapped. Run 'init' first" && ok || fail "expected bootstrap error: $out"

# 9. --check on garbage VERSION
TARGET4=$(make_v040_repo)
echo "9.0.0-garbage" > "$TARGET4/.collab/VERSION"
start_test "G1: --check on garbage VERSION errors with helpful message"
out=$( (cd "$TARGET4" && bash "$UPDATE" --check) 2>&1 || true)
echo "$out" | grep -q "invalid version" && ok || fail "expected invalid-version error: $out"

# ============================================================
# default mode (apply with confirmation)
# ============================================================

# 10. update --yes (apply silently)
TARGET5=$(make_v040_repo)
start_test "G1: update --yes runs migrations to shipped"
out=$( (cd "$TARGET5" && bash "$UPDATE" --yes) 2>&1)
ver=$(cat "$TARGET5/.collab/VERSION" | tr -d '[:space:]')
shipped=$(cat "$SKILL_ROOT/templates/collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "$shipped" ]] && ok || fail "expected $shipped, got $ver. out: $(echo "$out" | tail -10)"

# 11. update --yes writes UPGRADE_NOTES.md
start_test "G1: update --yes writes UPGRADE_NOTES.md"
[[ -f "$TARGET5/.collab/UPGRADE_NOTES.md" ]] && ok || fail "no UPGRADE_NOTES.md"

# 12. update --yes creates migration sentinels
start_test "G1: update --yes creates sentinels for each migration applied"
sentinel_count=$(ls "$TARGET5/.collab/.migrations/"*.applied 2>/dev/null | wc -l | tr -d ' ')
[[ "$sentinel_count" -ge 3 ]] && ok || fail "expected >= 3 sentinels, got $sentinel_count"

# 13. update --yes already-current
TARGET6=$(make_current_repo)
start_test "G1: update --yes on already-current install exits 0 with notice"
out=$( (cd "$TARGET6" && bash "$UPDATE" --yes) 2>&1)
echo "$out" | grep -q "Already up to date" && ok || fail "expected already-up-to-date; got: $out"

# 14. update --yes on newer-than-shipped (dev clone scenario)
TARGET7=$(make_current_repo)
echo "9.9.9" > "$TARGET7/.collab/VERSION"
start_test "G1: update --yes on newer-than-shipped install reports nothing-to-do"
out=$( (cd "$TARGET7" && bash "$UPDATE" --yes) 2>&1)
echo "$out" | grep -q "newer than shipped" && ok || fail "expected newer-than-shipped notice; got: $out"

# 15. Interactive accept (pipe 'y')
TARGET8=$(make_v040_repo)
start_test "G1: interactive accept via piped 'y' applies the upgrade"
out=$( (cd "$TARGET8" && printf 'y\n' | bash "$UPDATE") 2>&1)
ver=$(cat "$TARGET8/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "$shipped" ]] && ok || fail "expected $shipped after pipe-y, got $ver"

# 16. Interactive accept via empty Enter (default Y)
TARGET9=$(make_v040_repo)
start_test "G1: interactive accept via empty Enter (default Y) applies"
out=$( (cd "$TARGET9" && printf '\n' | bash "$UPDATE") 2>&1)
ver=$(cat "$TARGET9/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "$shipped" ]] && ok || fail "expected $shipped after pipe-empty, got $ver"

# 17. Interactive decline (pipe 'n')
TARGET10=$(make_v040_repo)
start_test "G1: interactive decline via piped 'n' leaves VERSION unchanged"
out=$( (cd "$TARGET10" && printf 'n\n' | bash "$UPDATE") 2>&1)
ver=$(cat "$TARGET10/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "0.4.0" ]] && echo "$out" | grep -q "Declined" && ok || \
  fail "expected decline + unchanged VERSION; got ver=$ver out=$out"

# 18. Interactive garbage input → treated as decline
TARGET11=$(make_v040_repo)
start_test "G1: interactive garbage input (e.g. 'maybe') treated as decline"
out=$( (cd "$TARGET11" && printf 'maybe\n' | bash "$UPDATE") 2>&1)
ver=$(cat "$TARGET11/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "0.4.0" ]] && ok || fail "garbage input not treated as decline; ver=$ver"

# 19. Closed stdin (EOF on read) without --yes
start_test "G1: closed stdin without --yes hard-fails with helpful message"
out=$( (cd "$(make_v040_repo)" && bash "$UPDATE" </dev/null) 2>&1 || true)
echo "$out" | grep -q "confirmation required" && ok || fail "expected confirmation-required error: $out"

# ============================================================
# --diff-first mode
# ============================================================

# 20. --diff-first --yes (skip second confirm, apply)
TARGET12=$(make_v040_repo)
start_test "G1: --diff-first --yes shows diff then applies"
out=$( (cd "$TARGET12" && bash "$UPDATE" --diff-first --yes) 2>&1)
ver=$(cat "$TARGET12/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "$shipped" ]] && ok || fail "expected $shipped after --diff-first --yes; got $ver"

# 21. --diff-first interactive decline
target=$(make_v040_repo)
start_test "G1: --diff-first decline (pipe 'n') leaves VERSION unchanged"
out=$( (cd "$target" && printf 'n\n' | bash "$UPDATE" --diff-first) 2>&1 || true)
ver=$(cat "$target/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "0.4.0" ]] && ok || fail "diff-first decline did not preserve VERSION; ver=$ver"
rm -rf "$target"

# ============================================================
# --rollback mode (CRITICAL — load-bearing for sentinel cleanup)
# ============================================================

# 22. --rollback with no backup
target=$(make_current_repo)
start_test "G1: --rollback with no backup reports 'nothing was changed'"
out=$( (cd "$target" && bash "$UPDATE" --rollback) 2>&1)
echo "$out" | grep -q "no backup to restore" && ok || fail "expected no-backup notice: $out"
rm -rf "$target"

# 23. Setup for the load-bearing rollback test:
#   v0.4.0 install -> update --yes -> update --rollback -> update --yes
#   Final state after re-upgrade MUST show migration bodies actually ran
#   (visible >>> Upgrade summary blocks). If sentinels weren't cleaned up,
#   the second --yes would silently skip migrations and produce no output.
target=$(make_v040_repo)

start_test "G1: phase 1 — initial v0.4.0 -> shipped upgrade succeeds"
out1=$( (cd "$target" && bash "$UPDATE" --yes) 2>&1)
ver=$(cat "$target/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "$shipped" ]] && ok || fail "phase 1 upgrade failed; ver=$ver"

start_test "G1: phase 2 — --rollback restores VERSION to 0.4.0"
out2=$( (cd "$target" && bash "$UPDATE" --rollback) 2>&1)
ver=$(cat "$target/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "0.4.0" ]] && ok || fail "rollback didn't restore VERSION; ver=$ver out=$out2"

start_test "G1: phase 2 — --rollback removes stale sentinels (CRITICAL)"
echo "$out2" | grep -qE "Removed [1-9][0-9]* stale sentinel" && ok || \
  fail "expected sentinel-removal notice; out: $out2"

start_test "G1: phase 2 — sentinels for migrations dst > 0.4.0 are gone"
# After rollback to 0.4.0, sentinels for 0.4.0→0.4.1, 0.4.1→0.4.2, 0.4.2→0.4.3
# should be deleted. (The 0.3.0→0.4.0 sentinel, if present from backfill, stays.)
[[ ! -f "$target/.collab/.migrations/0.4.0-to-0.4.1.applied" ]] && \
[[ ! -f "$target/.collab/.migrations/0.4.1-to-0.4.2.applied" ]] && \
[[ ! -f "$target/.collab/.migrations/0.4.2-to-0.4.3.applied" ]] && ok || \
  fail "stale sentinels not removed: $(ls "$target/.collab/.migrations/" 2>/dev/null)"

start_test "G1: phase 3 (LOAD-BEARING) — re-upgrade after rollback runs migration BODIES"
out3=$( (cd "$target" && bash "$UPDATE" --yes) 2>&1)
echo "$out3" | grep -q ">>> Upgrade summary" && ok || \
  fail "phase 3 failed: migrations were SKIPPED (sentinel cleanup broken). out: $out3"

start_test "G1: phase 3 — UPGRADE_NOTES.md written by re-upgrade"
[[ -f "$target/.collab/UPGRADE_NOTES.md" ]] && ok || \
  fail "no UPGRADE_NOTES.md after re-upgrade; migrations didn't run for real"

start_test "G1: phase 3 — VERSION advanced back to shipped"
ver=$(cat "$target/.collab/VERSION" | tr -d '[:space:]')
[[ "$ver" == "$shipped" ]] && ok || fail "VERSION not at shipped; got $ver"
rm -rf "$target"

# ============================================================
# --ack mode
# ============================================================

# 24. --ack archives UPGRADE_NOTES.md
target=$(make_v040_repo)
(cd "$target" && bash "$UPDATE" --yes) >/dev/null 2>&1

start_test "G1: --ack archives UPGRADE_NOTES.md"
out=$( (cd "$target" && bash "$UPDATE" --ack) 2>&1)
[[ ! -f "$target/.collab/UPGRADE_NOTES.md" ]] && \
  ls "$target/.collab/archive/UPGRADE_NOTES-"*.md >/dev/null 2>&1 && ok || \
  fail "UPGRADE_NOTES.md not archived; out=$out"

# 25. --ack on no-notes is a no-op
target2=$(make_current_repo)
start_test "G1: --ack with no UPGRADE_NOTES.md is a no-op"
out=$( (cd "$target2" && bash "$UPDATE" --ack) 2>&1)
echo "$out" | grep -q "nothing to do" && ok || fail "expected 'nothing to do'; got: $out"
rm -rf "$target" "$target2"

# ============================================================
# Mutual exclusion + arg validation
# ============================================================

# 26. Mode flags mutually exclusive
target=$(make_current_repo)
start_test "G1: --check --rollback rejected as mutually exclusive"
out=$( (cd "$target" && bash "$UPDATE" --check --rollback) 2>&1 || true)
echo "$out" | grep -qiE "mutually exclusive" && ok || fail "expected mutual-exclusion error: $out"

start_test "G1: --check --ack rejected as mutually exclusive"
out=$( (cd "$target" && bash "$UPDATE" --check --ack) 2>&1 || true)
echo "$out" | grep -qiE "mutually exclusive" && ok || fail "expected mutual-exclusion error: $out"

# 27. Unknown flag rejected
start_test "G1: unknown flag rejected with usage"
out=$( (cd "$target" && bash "$UPDATE" --bogus-xyz) 2>&1 || true)
echo "$out" | grep -q "unknown arg" && ok || fail "expected unknown-arg error: $out"
rm -rf "$target"

# 28. --help works
start_test "G1: --help prints usage"
out=$(bash "$UPDATE" --help 2>&1)
echo "$out" | grep -q "Usage: collab-update.sh" && ok || fail "expected usage; got: $out"

# 29. Default mode on non-bootstrapped repo
target=$(make_tmp_repo)
start_test "G1: default mode on non-bootstrapped repo errors"
out=$( (cd "$target" && bash "$UPDATE" --yes) 2>&1 || true)
echo "$out" | grep -q "not bootstrapped" && ok || fail "expected bootstrap error: $out"
rm -rf "$target"

report
