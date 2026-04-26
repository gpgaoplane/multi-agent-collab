#!/usr/bin/env bash
# Tests for vocabulary sections (C1, C2, C7, C8).
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
PROTOCOL="$SKILL_ROOT/templates/collab/PROTOCOL.md"

# --- C1: Sender handoff vocabulary ---
start_test "PROTOCOL.md documents sender vocabulary"
grep -q "wrap up for handoff" "$PROTOCOL" && ok || fail "sender phrase missing"

# --- C2: Receiver handoff vocabulary ---
start_test "PROTOCOL.md documents receiver vocabulary"
grep -q "take the baton" "$PROTOCOL" && ok || fail "receiver phrase missing"

# --- C7: Log rotation vocabulary ---
start_test "PROTOCOL.md has Log rotation vocabulary section"
grep -q "Log rotation vocabulary" "$PROTOCOL" && ok || fail "rotation vocabulary section missing"

start_test "rotation vocabulary lists key phrase 'rotate the log'"
grep -q "rotate the log" "$PROTOCOL" && ok || fail "phrase 'rotate the log' missing"

start_test "rotation vocabulary lists 'compact' phrasing"
grep -q "compact" "$PROTOCOL" && ok || fail "compact phrasing missing"

start_test "rotation vocabulary references collab-rotate-log.sh"
grep -q "collab-rotate-log.sh" "$PROTOCOL" && ok || fail "rotation command reference missing"

start_test "rotation vocabulary cautions against rotating another agent's log"
grep -q "never rotate another agent" "$PROTOCOL" && ok || fail "cross-agent caution missing"

# --- C8: Framework upgrade vocabulary ---
start_test "PROTOCOL.md has Framework upgrade vocabulary section"
grep -q "Framework upgrade vocabulary" "$PROTOCOL" && ok || fail "upgrade vocabulary section missing"

start_test "upgrade vocabulary lists 'update the framework'"
grep -q "update the framework" "$PROTOCOL" && ok || fail "phrase 'update the framework' missing"

start_test "upgrade vocabulary lists check-only 'is there a new version'"
grep -q "is there a new version" "$PROTOCOL" && ok || fail "check-only phrase missing"

start_test "upgrade vocabulary references collab-check.sh and init"
grep -q "collab-check.sh" "$PROTOCOL" && grep -q "collab-init.sh" "$PROTOCOL" && ok || fail "upgrade commands missing"

start_test "upgrade vocabulary references --ack-upgrade"
grep -q "ack-upgrade" "$PROTOCOL" && ok || fail "ack-upgrade reference missing"

start_test "upgrade vocabulary mentions cleanliness check (M2 dependency)"
grep -q "working tree is dirty" "$PROTOCOL" && ok || fail "dirty-tree caution missing"

report
