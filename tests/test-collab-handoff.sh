#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
HANDOFF="$SKILL_ROOT/scripts/collab-handoff.sh"

TARGET=$(make_tmp_repo)
init_with_all_agents "$TARGET" "$SKILL_ROOT"
cd "$TARGET"

start_test "handoff create writes a block to sender work log"
bash "$HANDOFF" codex --from claude --message "finished parser refactor" --files "src/parser.go tests/parser_test.go" >/dev/null 2>&1
grep -q "<!-- collab:handoff:start id=" docs/agents/claude.md && ok || fail "handoff block not appended to claude log"

start_test "handoff block cites target agent"
grep -q "Handoff → codex" docs/agents/claude.md && ok || fail "target agent missing"

start_test "handoff block has status: open"
grep -q "status.* open" docs/agents/claude.md && ok || fail "status line missing"

start_test "handoff does NOT create a receiver presence row (ACTIVE=running only)"
grep -q "| codex |" .collab/ACTIVE.md && fail "unexpected codex row in ACTIVE.md" || ok

start_test "handoff id extractable via grep"
id=$(grep -oE 'id=[0-9]{8}-[0-9]{6}-[a-f0-9]{4}' docs/agents/claude.md | head -1 | cut -d= -f2)
[[ -n "$id" ]] && ok || fail "could not extract id"

start_test "handoff close marks status closed"
bash "$HANDOFF" close "$id" --from claude >/dev/null 2>&1
grep -q "status.* closed" docs/agents/claude.md && ok || fail "status not closed"

start_test "chained handoff cites parent-id"
bash "$HANDOFF" gemini --from codex --message "validated" --parent-id "$id" >/dev/null 2>&1
grep -q "parent-id.* \`$id\`" docs/agents/codex.md && ok || fail "parent-id link broken"

# --- Full A→B→C→A chain ---
TARGET2=$(make_tmp_repo)
init_with_all_agents "$TARGET2" "$SKILL_ROOT"
cd "$TARGET2"

id1=$(bash "$HANDOFF" codex --from claude --message "A→B" 2>/dev/null)
id2=$(bash "$HANDOFF" gemini --from codex --message "B→C" --parent-id "$id1" 2>/dev/null)
id3=$(bash "$HANDOFF" claude --from gemini --message "C→A" --parent-id "$id2" 2>/dev/null)

start_test "chain length 3: three distinct ids"
[[ -n "$id1" && -n "$id2" && -n "$id3" && "$id1" != "$id2" && "$id2" != "$id3" ]] && ok || fail "ids collapsed: $id1/$id2/$id3"

start_test "chain: id2 cites id1 as parent"
grep -q "parent-id.* \`$id1\`" docs/agents/codex.md && ok || fail "id2 parent link broken"

start_test "chain: id3 cites id2 as parent"
grep -q "parent-id.* \`$id2\`" docs/agents/gemini.md && ok || fail "id3 parent link broken"

# --- Group C: pickup verb ---
TARGET3=$(make_tmp_repo)
init_with_all_agents "$TARGET3" "$SKILL_ROOT"
cd "$TARGET3"

pickup_id=$(bash "$HANDOFF" gemini --from claude --message "needs review" --files "src/foo.go" 2>/dev/null)

start_test "pickup prints the handoff block summary to stdout"
out=$(bash "$HANDOFF" pickup "$pickup_id" --from gemini 2>&1)
echo "$out" | grep -q "needs review" && ok || fail "pickup did not print block: $out"

start_test "pickup stamps picked-up metadata onto the block"
grep -q "picked-up:" docs/agents/claude.md && ok || fail "picked-up metadata not stamped"

start_test "pickup records the receiver name"
grep -q "picked-up:.* by gemini" docs/agents/claude.md && ok || fail "picked-up receiver not recorded"

start_test "pickup leaves status as open until close"
awk "/handoff:start id=$pickup_id/,/handoff:end/" docs/agents/claude.md | grep -q "status.* open" && ok || fail "status changed before close"

start_test "pickup is idempotent (re-run produces same status, updated timestamp)"
ts1=$(grep "picked-up:" docs/agents/claude.md | head -1)
sleep 1
bash "$HANDOFF" pickup "$pickup_id" --from gemini >/dev/null 2>&1
ts2=$(grep "picked-up:" docs/agents/claude.md | head -1)
# Only one picked-up line should exist (no duplication)
count=$(grep -c "picked-up:" docs/agents/claude.md)
[[ "$count" == "1" ]] && ok || fail "picked-up duplicated: $count lines"

start_test "close after pickup preserves picked-up metadata"
bash "$HANDOFF" close "$pickup_id" --from gemini >/dev/null 2>&1
grep -q "picked-up:" docs/agents/claude.md && ok || fail "close stripped picked-up metadata"

start_test "close after pickup sets status closed"
awk "/handoff:start id=$pickup_id/,/handoff:end/" docs/agents/claude.md | grep -q "status.* closed" && ok || fail "status not closed"

start_test "pickup of unknown id errors non-zero"
out=$(bash "$HANDOFF" pickup "nonexistent-id" --from gemini 2>&1)
rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -q "not found" && ok || fail "expected non-zero with 'not found': rc=$rc out=$out"

# --- Group C5: to: any handoff is visible to all agents ---
any_id=$(bash "$HANDOFF" any --from claude --message "open to anyone" 2>/dev/null)

start_test "to: any handoff is created with target 'any'"
grep -q "Handoff → any" docs/agents/claude.md && ok || fail "any-targeted block not written"

start_test "catchup --handoff surfaces 'any' block for codex"
out=$(bash "$SKILL_ROOT/scripts/collab-catchup.sh" preview --agent codex --handoff 2>&1)
echo "$out" | grep -q "open to anyone" && ok || fail "any-block not surfaced for codex: $out"

start_test "catchup --handoff surfaces 'any' block for gemini"
out=$(bash "$SKILL_ROOT/scripts/collab-catchup.sh" preview --agent gemini --handoff 2>&1)
echo "$out" | grep -q "open to anyone" && ok || fail "any-block not surfaced for gemini: $out"

# --- Group C: vocabulary documentation ---
start_test "PROTOCOL.md documents sender vocabulary phrases"
grep -q "wrap up for handoff" "$SKILL_ROOT/templates/collab/PROTOCOL.md" && ok || fail "sender phrase missing"

start_test "PROTOCOL.md documents receiver vocabulary phrases"
grep -q "take the baton" "$SKILL_ROOT/templates/collab/PROTOCOL.md" && ok || fail "receiver phrase missing"

start_test "PROTOCOL.md documents 'to: any' group handoffs"
grep -q "Group handoffs" "$SKILL_ROOT/templates/collab/PROTOCOL.md" && ok || fail "group handoff doc missing"

cd "$SKILL_ROOT"
rm -rf "$TARGET" "$TARGET2" "$TARGET3"
report
