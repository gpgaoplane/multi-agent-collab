#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP"' EXIT

cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

(cd "$TMP" && bash scripts/collab-init.sh)

# User customizes Claude adapter OUTSIDE managed markers.
cat >> "$TMP/.claude/CLAUDE.md" <<'EOF'

## User's custom section (outside markers)
This must survive re-init.
EOF

# User writes a new work-log entry.
cat >> "$TMP/docs/agents/claude.md" <<'EOF'

## 2026-04-22T12:00:00-05:00 — Custom entry
This entry should survive re-init.
EOF

# Re-run init in re-init mode.
(cd "$TMP" && bash scripts/collab-init.sh)

start_test "re-init preserves user content outside markers in adapter"
assert_file_contains "$TMP/.claude/CLAUDE.md" "User's custom section (outside markers)"

start_test "re-init preserves appended work-log entry"
assert_file_contains "$TMP/docs/agents/claude.md" "Custom entry"

start_test "re-init does not duplicate managed content"
count=$(grep -c '<!-- collab:behavioral-rules:start -->' "$TMP/AI_AGENTS.md" || true)
assert_eq "1" "$count"

start_test "re-init still passes collab-check"
(cd "$TMP" && bash scripts/collab-check.sh) && ok || fail "check failed after re-init"

report
