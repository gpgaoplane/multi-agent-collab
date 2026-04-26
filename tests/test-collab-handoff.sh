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

cd "$SKILL_ROOT"
rm -rf "$TARGET" "$TARGET2"
report
