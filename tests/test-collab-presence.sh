#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
PRESENCE="$SKILL_ROOT/scripts/collab-presence.sh"

TARGET=$(make_tmp_repo)
cd "$TARGET"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1

start_test "presence start writes a row"
bash "$PRESENCE" start --agent claude --session abc123 >/dev/null 2>&1
grep -q "| claude | abc123 |" .collab/ACTIVE.md && ok || fail "row missing after start"

start_test "presence start is idempotent (same agent+session updates, not duplicates)"
bash "$PRESENCE" start --agent claude --session abc123 >/dev/null 2>&1
count=$(grep -c "| claude | abc123 |" .collab/ACTIVE.md || true)
[[ "$count" == "1" ]] && ok || fail "expected 1 row, got $count"

start_test "presence end removes the row"
bash "$PRESENCE" end --agent claude --session abc123 >/dev/null 2>&1
grep -q "| claude | abc123 |" .collab/ACTIVE.md && fail "row still present after end" || ok

start_test "presence end of missing row is true no-op (file byte-identical)"
cp .collab/ACTIVE.md /tmp/active-before
bash "$PRESENCE" end --agent claude --session doesnotexist >/dev/null 2>&1
diff -q /tmp/active-before .collab/ACTIVE.md >/dev/null && ok || fail "end mutated ACTIVE.md on missing row"
rm -f /tmp/active-before

start_test "missing --agent errors with a helpful message"
err=$(bash "$PRESENCE" start --session abc 2>&1 >/dev/null; echo "exit=$?")
echo "$err" | grep -q "agent is required" && echo "$err" | grep -q "exit=1" && ok || fail "wrong error path: $err"

cd "$SKILL_ROOT"
rm -rf "$TARGET"
report
