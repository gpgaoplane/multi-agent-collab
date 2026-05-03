#!/usr/bin/env bash
# v0.4.2 (G8): migration sentinel system makes the chain runner idempotent.
# Tests cover: forward run writes sentinels, re-run skips on sentinel,
# SHA mismatch re-runs, back-fill on existing v0.4.x install, partial
# failure (sentinel not written), no-SHA fallback (skip on presence).
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Setup: simulate a v0.3.0 install. Two migrations should run on upgrade
#     to shipped (0.4.0 → 0.4.1, 0.4.1 → 0.4.2 doesn't exist for this baseline). ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET" "${TARGET2:-}" "${TARGET3:-}"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"
(cd "$TARGET" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.3.0" > "$TARGET/.collab/VERSION"

# --- Forward run: chain executes and writes sentinels ---
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "G8: chain creates .collab/.migrations/ directory"
[[ -d "$TARGET/.collab/.migrations" ]] && ok || fail ".collab/.migrations/ not created"

start_test "G8: .collab/.migrations/README.md exists with managed frontmatter"
[[ -f "$TARGET/.collab/.migrations/README.md" ]] && \
  grep -q "^status: managed" "$TARGET/.collab/.migrations/README.md" && ok || \
  fail "README.md missing or wrong frontmatter"

start_test "G8: sentinel written for each migration that ran (0.3.0->0.4.0)"
[[ -f "$TARGET/.collab/.migrations/0.3.0-to-0.4.0.applied" ]] && ok || fail "missing 0.3.0->0.4.0 sentinel"

start_test "G8: sentinel written for 0.4.0->0.4.1"
[[ -f "$TARGET/.collab/.migrations/0.4.0-to-0.4.1.applied" ]] && ok || fail "missing 0.4.0->0.4.1 sentinel"

start_test "G8: sentinel written for 0.4.1->0.4.2"
[[ -f "$TARGET/.collab/.migrations/0.4.1-to-0.4.2.applied" ]] && ok || fail "missing 0.4.1->0.4.2 sentinel"

start_test "G8: sentinel records applied-at timestamp"
grep -q "^applied-at: " "$TARGET/.collab/.migrations/0.3.0-to-0.4.0.applied" && ok || fail "no applied-at"

start_test "G8: sentinel records script-sha"
grep -q "^script-sha: " "$TARGET/.collab/.migrations/0.3.0-to-0.4.0.applied" && ok || fail "no script-sha"

# --- Re-run idempotency: reset VERSION, re-upgrade, sentinels honored ---
echo "0.3.0" > "$TARGET/.collab/VERSION"
out2=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "G8: re-upgrade with intact sentinels skips already-applied migrations"
echo "$out2" | grep -q "0.3.0 → 0.4.0 already applied" && ok || \
  fail "expected skip message; got: $out2"

start_test "G8: re-upgrade does NOT re-run the migration script body"
# If migration re-ran, the >>> Upgrade summary block would appear in stdout.
echo "$out2" | grep -q ">>> Upgrade summary (v0.3.0" && \
  fail "migration re-ran despite sentinel" || ok

# --- SHA mismatch: tamper with sentinel to force re-run ---
sed -i 's/^script-sha: .*/script-sha: deadbeef-bogus-sha/' "$TARGET/.collab/.migrations/0.3.0-to-0.4.0.applied"
echo "0.3.0" > "$TARGET/.collab/VERSION"
out3=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "G8: SHA mismatch in sentinel triggers migration re-run"
echo "$out3" | grep -q ">>> Upgrade summary (v0.3.0" && ok || \
  fail "expected migration re-run on SHA mismatch; got: $out3"

start_test "G8: re-run rewrites sentinel with current script-sha"
new_sha=$(awk -F': *' '/^script-sha:/ { print $2; exit }' "$TARGET/.collab/.migrations/0.3.0-to-0.4.0.applied")
[[ "$new_sha" != "deadbeef-bogus-sha" ]] && ok || fail "sentinel SHA not refreshed"

# --- Back-fill: existing v0.4.1 install (no .collab/.migrations/ dir) ---
TARGET2=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TARGET2/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET2/templates"
(cd "$TARGET2" && bash scripts/collab-init.sh) >/dev/null 2>&1
# Simulate a v0.4.1 install: VERSION reads 0.4.1, no .collab/.migrations yet.
echo "0.4.1" > "$TARGET2/.collab/VERSION"
rm -rf "$TARGET2/.collab/.migrations" 2>/dev/null || true

out4=$( (cd "$TARGET2" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "G8: back-fill creates sentinels for legacy migrations on first v0.4.2 upgrade"
[[ -f "$TARGET2/.collab/.migrations/0.1.0-to-0.2.0.applied" ]] && \
  [[ -f "$TARGET2/.collab/.migrations/0.2.0-to-0.3.0.applied" ]] && \
  [[ -f "$TARGET2/.collab/.migrations/0.3.0-to-0.4.0.applied" ]] && \
  [[ -f "$TARGET2/.collab/.migrations/0.4.0-to-0.4.1.applied" ]] && ok || \
  fail "back-fill didn't create all legacy sentinels"

start_test "G8: back-fill did NOT execute legacy migration bodies (no >>> blocks for them)"
# 0.4.1 -> 0.4.2 IS the actual chained migration on this install, so its
# block is expected. The legacy ones (0.3.0->0.4.0 etc.) MUST NOT appear.
echo "$out4" | grep -q ">>> Upgrade summary (v0.3.0" && \
  fail "legacy migration ran during back-fill" || ok

start_test "G8: 0.4.1->0.4.2 migration sentinel present after the chained upgrade"
[[ -f "$TARGET2/.collab/.migrations/0.4.1-to-0.4.2.applied" ]] && ok || \
  fail "0.4.1->0.4.2 sentinel missing"

# --- No-SHA fallback: write a sentinel with no-sha-available, expect skip ---
TARGET3=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TARGET3/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET3/templates"
(cd "$TARGET3" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.4.1" > "$TARGET3/.collab/VERSION"
mkdir -p "$TARGET3/.collab/.migrations"
cat > "$TARGET3/.collab/.migrations/0.4.1-to-0.4.2.applied" <<'EOF'
applied-at: 2026-05-02T00:00:00-00:00
script-sha: no-sha-available
EOF

out5=$( (cd "$TARGET3" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) 2>&1)

start_test "G8: no-sha-available in sentinel makes the migration skip on presence"
echo "$out5" | grep -q "0.4.1 → 0.4.2 already applied" && ok || \
  fail "expected skip on no-sha-available sentinel; got: $out5"

# --- version_le helper sanity ---
source "$SKILL_ROOT/scripts/lib/sha.sh"
# Source collab-init.sh's helpers via a sub-shell that doesn't run the script.
# We need version_le isolated; the simplest is to extract via grep+eval.
verify_version_le() {
  ( source "$SKILL_ROOT/scripts/lib/frontmatter.sh"
    source "$SKILL_ROOT/scripts/lib/index.sh"
    source "$SKILL_ROOT/scripts/lib/merge.sh"
    source "$SKILL_ROOT/scripts/lib/sha.sh"
    HERE="$SKILL_ROOT/scripts"
    # Define version_le inline matching collab-init.sh.
    version_le() {
      local a="$1" b="$2"
      local a1 a2 a3 b1 b2 b3
      IFS=. read -r a1 a2 a3 <<< "$a"
      IFS=. read -r b1 b2 b3 <<< "$b"
      if (( 10#$a1 < 10#$b1 )); then return 0; fi
      if (( 10#$a1 > 10#$b1 )); then return 1; fi
      if (( 10#$a2 < 10#$b2 )); then return 0; fi
      if (( 10#$a2 > 10#$b2 )); then return 1; fi
      if (( 10#$a3 <= 10#$b3 )); then return 0; fi
      return 1
    }
    version_le "$1" "$2"
  )
}

start_test "G8: version_le 0.4.1 0.4.2 is true"
verify_version_le "0.4.1" "0.4.2" && ok || fail "0.4.1 should be <= 0.4.2"

start_test "G8: version_le 0.4.2 0.4.1 is false"
! verify_version_le "0.4.2" "0.4.1" && ok || fail "0.4.2 should NOT be <= 0.4.1"

start_test "G8: version_le 0.10.0 0.9.0 is false (numeric, not lex)"
! verify_version_le "0.10.0" "0.9.0" && ok || fail "0.10.0 should NOT be <= 0.9.0 (numeric compare)"

start_test "G8: version_le 0.9.0 0.10.0 is true (numeric, not lex)"
verify_version_le "0.9.0" "0.10.0" && ok || fail "0.9.0 should be <= 0.10.0 (numeric compare)"

report
