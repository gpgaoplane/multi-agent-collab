#!/usr/bin/env bash
# v0.4.2 (G9): inject_agents_md_section avoids appending duplicate sections.
# Also confirms G7+G9 interaction: pre-existing duplicate markers don't block
# init (warning emitted, init continues).
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

count_markers() {
  local file="$1"
  local section="$2"
  grep -cF "<!-- collab:${section}:start -->" "$file"
}

# --- Healthy upgrade-restore-reinit cycle: no duplicates ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET" "${TARGET2:-}" "${TARGET3:-}"' EXIT
cd "$TARGET"
bash "$SKILL_ROOT/scripts/collab-init.sh" --agent claude >/dev/null 2>&1

start_test "G9: fresh init produces exactly one critical-rules block in AGENTS.md"
n=$(count_markers AGENTS.md "critical-rules")
[[ "$n" == "1" ]] && ok || fail "expected 1 critical-rules block, got $n"

start_test "G9: re-init does NOT duplicate the critical-rules block"
bash "$SKILL_ROOT/scripts/collab-init.sh" --agent claude >/dev/null 2>&1
n=$(count_markers AGENTS.md "critical-rules")
[[ "$n" == "1" ]] && ok || fail "re-init duplicated the block (count=$n)"

# --- Orphan start marker → inject does NOT append a fresh block ---
TARGET2=$(make_tmp_repo)
cd "$TARGET2"
bash "$SKILL_ROOT/scripts/collab-init.sh" --agent claude >/dev/null 2>&1
# Surgically remove the END marker for critical-rules to create an orphan start.
awk '
  /^<!-- collab:critical-rules:end -->$/ { next }
  { print }
' AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
orphan_count=$(grep -c "<!-- collab:critical-rules:" AGENTS.md)

start_test "G9: orphan-start fixture has 1 marker line (precondition)"
[[ "$orphan_count" == "1" ]] && ok || fail "expected 1 orphan marker line, got $orphan_count"

start_test "G9: re-init with orphan start emits warning, does NOT append duplicate"
out=$(bash "$SKILL_ROOT/scripts/collab-init.sh" --agent claude 2>&1)
echo "$out" | grep -q "orphan marker" && ok || fail "no orphan-marker warning emitted: $out"

start_test "G9: orphan start case — no second start marker introduced"
n=$(count_markers AGENTS.md "critical-rules")
[[ "$n" == "1" ]] && ok || fail "duplicate start marker introduced (count=$n)"

# --- Pre-existing duplicate markers → init continues with warning, no failure ---
TARGET3=$(make_tmp_repo)
cd "$TARGET3"
bash "$SKILL_ROOT/scripts/collab-init.sh" --agent claude >/dev/null 2>&1
# Hand-corrupt: duplicate the critical-rules marker pair.
duplicate_block=$(awk '
  /^<!-- collab:critical-rules:start -->$/ { in_blk=1 }
  in_blk { print }
  /^<!-- collab:critical-rules:end -->$/ { in_blk=0 }
' AGENTS.md)
{
  cat AGENTS.md
  echo
  printf '%s\n' "$duplicate_block"
} > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
pre_count=$(count_markers AGENTS.md "critical-rules")

start_test "G7+G9: corrupted AGENTS.md has duplicate markers (precondition)"
[[ "$pre_count" == "2" ]] && ok || fail "expected 2 start markers as setup, got $pre_count"

start_test "G7+G9: re-init on duplicate-marker file does NOT exit non-zero"
out=$(bash "$SKILL_ROOT/scripts/collab-init.sh" --agent claude 2>&1)
status=$?
[[ "$status" == "0" ]] && ok || fail "init exited $status on duplicate-marker file: $out"

start_test "G7: doubled-marker warning visible to user"
echo "$out" | grep -q "duplicate start markers" && ok || fail "no duplicate-marker warning: $out"

start_test "G9 documented limitation: existing duplicates not auto-cleaned"
# G9 prevents future duplication but does NOT clean existing duplicates.
post_count=$(count_markers AGENTS.md "critical-rules")
[[ "$post_count" == "2" ]] && ok || fail "duplicate count changed unexpectedly (was 2, now $post_count)"

cd "$SKILL_ROOT"
report
