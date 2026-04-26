#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# Simulate user's home skills dir.
FAKE_HOME=$(mktemp -d)
SKILL_DIR="$FAKE_HOME/.claude/skills/multi-agent-collab"
mkdir -p "$(dirname "$SKILL_DIR")"
cp -R "$SKILL_ROOT" "$SKILL_DIR"

# Target repo where the user actually works.
TARGET=$(make_tmp_repo)

trap 'rm -rf "$FAKE_HOME" "$TARGET"' EXIT

start_test "SKILL.md exists at skill-dir root"
assert_file_exists "$SKILL_DIR/SKILL.md"

source "$SKILL_DIR/scripts/lib/frontmatter.sh"

start_test "SKILL.md has valid name field"
assert_eq "multi-agent-collab" "$(fm_get_field "$SKILL_DIR/SKILL.md" name)"

start_test "SKILL.md has non-empty description"
desc=$(fm_get_field "$SKILL_DIR/SKILL.md" description)
[[ -n "$desc" ]] && ok || fail "description empty"

start_test "SKILL.md version matches shipped templates VERSION"
ver=$(fm_get_field "$SKILL_DIR/SKILL.md" version)
shipped=$(cat "$SKILL_DIR/templates/collab/VERSION" | tr -d '[:space:]')
assert_eq "$shipped" "$ver"

start_test "SKILL.md body includes state-check guard instruction"
assert_file_contains "$SKILL_DIR/SKILL.md" "Step 1: Check current state"
assert_file_contains "$SKILL_DIR/SKILL.md" ".collab/VERSION"

start_test "running installer from skill-dir bootstraps target repo"
(cd "$TARGET" && bash "$SKILL_DIR/scripts/collab-init.sh") >/dev/null 2>&1
assert_file_exists "$TARGET/AI_AGENTS.md"
assert_file_exists "$TARGET/AGENTS.md"
assert_file_exists "$TARGET/.collab/VERSION"
assert_eq "$shipped" "$(cat "$TARGET/.collab/VERSION" | tr -d '[:space:]')"

start_test "re-invoking from skill-dir on installed repo is idempotent"
(cd "$TARGET" && bash "$SKILL_DIR/scripts/collab-init.sh") >/dev/null 2>&1
# No duplicate markers.
count=$(grep -c '<!-- collab:behavioral-rules:start -->' "$TARGET/AI_AGENTS.md" || true)
assert_eq "1" "$count"

start_test "post-bootstrap collab-check passes"
(cd "$TARGET" && bash "$SKILL_DIR/scripts/collab-check.sh") >/dev/null 2>&1 && ok || fail "check failed"

report
