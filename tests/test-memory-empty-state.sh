#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TARGET=$(make_tmp_repo)
cd "$TARGET"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1

start_test "context.md empty-state is visibly intentional"
grep -qi "has not completed a substantive task" .claude/memory/context.md && ok || fail "placeholder text unchanged"

start_test "decisions.md empty-state is visibly intentional"
grep -qi "no durable decisions recorded yet" .claude/memory/decisions.md && ok || fail "placeholder text unchanged"

start_test "pitfalls.md empty-state is visibly intentional"
grep -qi "no pitfalls documented yet" .claude/memory/pitfalls.md && ok || fail "placeholder text unchanged"

start_test "state.md next-steps empty-state is visibly intentional"
grep -qi "no next steps queued" .claude/memory/state.md && ok || fail "placeholder text unchanged"

cd "$SKILL_ROOT"
rm -rf "$TARGET"
report
