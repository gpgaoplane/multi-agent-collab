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

start_test "--add-agent without descriptor errors cleanly"
out=$( (cd "$TMP" && bash scripts/collab-init.sh --add-agent cursor 2>&1) || true)
assert_contains "descriptor" "$out"

# Create the cursor descriptor manually (simulating the wizard steps).
cat > "$TMP/.collab/agents.d/cursor.yml" <<'EOF'
name: cursor
display: Cursor
adapter_path: .cursor/CURSOR.md
memory_dir: .cursor/memory
log_path: docs/agents/cursor.md
platform:
  config_discovery:
    - .cursor/CURSOR.md
  trigger_type: script-only
  bootstrap_command: "./scripts/collab-init.sh"
  supports_hooks: false
notes: |
  Test-only adapter for integration verification.
EOF

(cd "$TMP" && bash scripts/collab-init.sh --add-agent cursor)

start_test "--add-agent generates cursor adapter"
assert_file_exists "$TMP/.cursor/CURSOR.md"

start_test "--add-agent generates cursor memory"
assert_file_exists "$TMP/.cursor/memory/state.md"

start_test "--add-agent generates cursor work log"
assert_file_exists "$TMP/docs/agents/cursor.md"

start_test "--add-agent registers new files in INDEX"
assert_file_contains "$TMP/.collab/INDEX.md" ".cursor/CURSOR.md"

report
