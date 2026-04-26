#!/usr/bin/env bash
# Tests for M4: collab-init --diff flag.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Setup: v0.3.0 install committed cleanly ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"
(cd "$TARGET" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.3.0" > "$TARGET/.collab/VERSION"
(cd "$TARGET" && git add -A && git commit -q -m "bootstrap")

# Capture pre-diff state for comparison.
pre_ai_agents=$(md5sum "$TARGET/AI_AGENTS.md" | cut -d' ' -f1)
pre_version=$(cat "$TARGET/.collab/VERSION")

# --- --diff exits without modifying files ---
out=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --diff) 2>&1)

start_test "--diff exits with rc=0"
echo "$out" | tail -1
rc_check=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --diff) >/dev/null 2>&1; echo $?)
[[ "$rc_check" == "0" ]] && ok || fail "--diff returned non-zero: $rc_check"

start_test "--diff prints 'Migration diff' header"
echo "$out" | grep -q "Migration diff" && ok || fail "no diff header in output"

start_test "--diff output is restored marker after diff"
echo "$out" | grep -q "Restoring repo from backup" && ok || fail "no restoration marker"

start_test "--diff does NOT modify AI_AGENTS.md"
post_ai_agents=$(md5sum "$TARGET/AI_AGENTS.md" | cut -d' ' -f1)
assert_eq "$pre_ai_agents" "$post_ai_agents"

start_test "--diff does NOT modify VERSION"
post_version=$(cat "$TARGET/.collab/VERSION")
assert_eq "$pre_version" "$post_version"

start_test "--diff does NOT leave UPGRADE_NOTES.md behind"
[[ ! -f "$TARGET/.collab/UPGRADE_NOTES.md" ]] && ok || fail "UPGRADE_NOTES.md leaked from --diff run"

start_test "--diff does NOT leave a backup directory behind"
ls -d "$TARGET/.collab/backup/0.3.0-to-"*/ >/dev/null 2>&1 && fail "backup dir leaked from --diff run" || ok

# --- Diff output mentions a file that v0.4.0 actually changes ---
start_test "--diff output mentions AI_AGENTS.md (which v0.4.0 modifies via marker refresh)"
echo "$out" | grep -q "AI_AGENTS.md" && ok || fail "expected AI_AGENTS.md in diff output"

start_test "--diff output uses unified-diff hunk markers (--- / +++ )"
echo "$out" | grep -E '^---|^\+\+\+' >/dev/null && ok || fail "no diff hunks present"

# --- --diff after upgrade shows no changes ---
(cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh) >/dev/null 2>&1

start_test "post-upgrade --diff reports no file-level changes"
out2=$( (cd "$TARGET" && COLLAB_MIGRATE_NONINTERACTIVE=1 bash scripts/collab-init.sh --diff) 2>&1)
# In re-init mode (current = shipped), --diff has no migrations to run; the
# shouldn't even enter upgrade case. Expect MODE: re-init.
echo "$out2" | grep -q "Mode: re-init" && ok || fail "expected re-init mode after upgrade: $(echo "$out2" | head -3)"

report
