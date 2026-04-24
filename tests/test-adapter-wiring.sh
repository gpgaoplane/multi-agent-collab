#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TARGET=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"
cd "$TARGET"
bash "$TARGET/scripts/collab-init.sh" >/dev/null 2>&1

start_test "bootstrapped PROTOCOL.md references collab-handoff"
grep -q "collab-handoff" .collab/PROTOCOL.md && ok || fail "PROTOCOL.md does not teach handoff"

start_test "bootstrapped ROUTING.md has a handoff row"
grep -qi "handoff" .collab/ROUTING.md && ok || fail "ROUTING.md missing handoff row"

start_test "bootstrapped per-agent adapter references collab-handoff"
# Find the Claude adapter file — it could be .claude/CLAUDE.md or similar.
# Read the descriptor to find it.
adapter=$(awk -F': *' '/^adapter_path:/ { print $2 }' .collab/agents.d/claude.yml)
grep -q "collab-handoff" "$adapter" && ok || fail "claude adapter at $adapter does not teach handoff"

start_test "adapter mentions take-the-baton or pick-up-handoff vocabulary"
grep -qiE "take the baton|pick up handoff" "$adapter" && ok || fail "user-facing phrase missing from $adapter"

cd "$SKILL_ROOT"
rm -rf "$TARGET"
report
