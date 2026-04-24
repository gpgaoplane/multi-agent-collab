#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- v0.2.0 → v0.3.0 direct path ---
TARGET=$(make_tmp_repo)
cd "$TARGET"

# Simulate a v0.2.0 install.
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1
echo "0.2.0" > .collab/VERSION

start_test "upgrade to 0.3.0 runs migration and bumps version"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1
[[ "$(cat .collab/VERSION)" == "0.3.0" ]] && ok || fail "version not bumped: $(cat .collab/VERSION)"

start_test "migration installs .collab/config.yml"
[[ -f .collab/config.yml ]] && grep -qE '^strict:\s*false' .collab/config.yml && ok || fail "config.yml missing post-upgrade"

start_test "migration leaves user custom memory intact"
echo "custom line by user" > /tmp/custom.md
cat .claude/memory/context.md /tmp/custom.md > /tmp/patched.md
mv /tmp/patched.md .claude/memory/context.md
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1
grep -q "custom line by user" .claude/memory/context.md && ok || fail "user content lost"

cd "$SKILL_ROOT"
rm -rf "$TARGET"

# --- Direct 0.1.0 → 0.3.0 skip-migration path ---
# Users who never ran 0.2.0 should still end up at 0.3.0 with AGENTS.md (from
# 0.2.0's migration) AND config.yml (from 0.3.0's migration).
TARGET2=$(make_tmp_repo)
cd "$TARGET2"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1
echo "0.1.0" > .collab/VERSION
rm -f AGENTS.md .collab/config.yml  # state that mirrors a true 0.1.0 install

bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1

start_test "skip-migration: 0.1.0 → 0.3.0 arrives at 0.3.0"
[[ "$(cat .collab/VERSION)" == "0.3.0" ]] && ok || fail "version stuck at $(cat .collab/VERSION)"

start_test "skip-migration: AGENTS.md installed (from 0.2.0 migration)"
[[ -f AGENTS.md ]] && ok || fail "AGENTS.md missing — did 0.1.0→0.2.0 run?"

start_test "skip-migration: config.yml installed (from 0.3.0 migration)"
[[ -f .collab/config.yml ]] && ok || fail "config.yml missing — did 0.2.0→0.3.0 run?"

cd "$SKILL_ROOT"
rm -rf "$TARGET2"
report
