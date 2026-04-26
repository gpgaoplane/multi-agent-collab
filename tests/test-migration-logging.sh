#!/usr/bin/env bash
# Tests for M5: loud per-migration logging.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- 0.1.0 -> 0.2.0 emits BEFORE/AFTER for AGENTS.md ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"
(cd "$TARGET" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.1.0" > "$TARGET/.collab/VERSION"
rm -f "$TARGET/AGENTS.md"  # 0.1.0-era state

out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --no-backup --force-dirty) 2>&1)

start_test "0.1.0->0.2.0 emits BEFORE line for AGENTS.md (not present)"
echo "$out" | grep -E '\[migration log\] BEFORE: .*AGENTS\.md.*not present' >/dev/null && ok || fail "expected BEFORE not-present line: $(echo "$out" | grep -E 'migration log' | head -3)"

start_test "0.1.0->0.2.0 emits AFTER line for AGENTS.md with line+marker counts"
echo "$out" | grep -E '\[migration log\] AFTER:.*AGENTS\.md.*[0-9]+ lines.*[0-9]+ marker' >/dev/null && ok || fail "expected AFTER line+marker counts"

# --- 0.2.0 -> 0.3.0 emits BEFORE/AFTER for config.yml ---
TARGET2=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TARGET2/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET2/templates"
(cd "$TARGET2" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.2.0" > "$TARGET2/.collab/VERSION"
rm -f "$TARGET2/.collab/config.yml"  # 0.2.0-era state

out2=$( (cd "$TARGET2" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --no-backup --force-dirty) 2>&1)

start_test "0.2.0->0.3.0 emits BEFORE line for config.yml (not present)"
echo "$out2" | grep -E '\[migration log\] BEFORE: .*config\.yml.*not present' >/dev/null && ok || fail "expected BEFORE not-present line for config.yml"

start_test "0.2.0->0.3.0 emits AFTER line for config.yml with counts"
echo "$out2" | grep -E '\[migration log\] AFTER:.*config\.yml.*[0-9]+ lines' >/dev/null && ok || fail "expected AFTER line for config.yml"

# --- 0.3.0 -> 0.4.0 emits BEFORE/AFTER agent descriptor counts ---
TARGET3=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TARGET3/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET3/templates"
init_with_all_agents "$TARGET3" "$SKILL_ROOT"
echo "0.3.0" > "$TARGET3/.collab/VERSION"

out3=$( (cd "$TARGET3" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --no-backup --force-dirty) 2>&1)

start_test "0.3.0->0.4.0 emits BEFORE descriptor count"
echo "$out3" | grep -E '\[migration log\] BEFORE: 3 agent descriptor' >/dev/null && ok || fail "expected BEFORE: 3 descriptors"

start_test "0.3.0->0.4.0 emits AFTER descriptor count (non-interactive keeps 3)"
echo "$out3" | grep -E '\[migration log\] AFTER: 3 agent descriptor' >/dev/null && ok || fail "expected AFTER: 3 descriptors (kept all)"

# --- AFTER count drops when REMOVE_ALL_SEED prunes ---
TARGET4=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TARGET4/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET4/templates"
init_with_all_agents "$TARGET4" "$SKILL_ROOT"
echo "0.3.0" > "$TARGET4/.collab/VERSION"

out4=$( (cd "$TARGET4" && COLLAB_MIGRATE_NONINTERACTIVE=1 COLLAB_MIGRATE_REMOVE_ALL_SEED=1 COLLAB_AGENT=claude bash scripts/collab-init.sh --no-backup --force-dirty) 2>&1)

start_test "0.3.0->0.4.0 emits 'removed agent' lines for pruned agents"
echo "$out4" | grep -E '\[migration log\] removed agent: codex' >/dev/null && ok || fail "expected removed-agent log for codex"

start_test "0.3.0->0.4.0 AFTER count reflects pruning (caller claude survives, others removed)"
echo "$out4" | grep -E '\[migration log\] AFTER: 1 agent descriptor' >/dev/null && ok || fail "expected AFTER: 1 descriptor"

report
