#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP" "${TMP2:-}"' EXIT

cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

# User arrives with a pre-existing AGENTS.md.
cat > "$TMP/AGENTS.md" <<'EOF'
# Pre-existing AGENTS.md from user

## Custom section
This must survive bootstrap.
EOF

(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1

start_test "bootstrap preserves pre-existing AGENTS.md user content"
assert_file_contains "$TMP/AGENTS.md" "Custom section"
assert_file_contains "$TMP/AGENTS.md" "This must survive bootstrap."

start_test "bootstrap injects skill-managed AGENTS.md section"
assert_file_contains "$TMP/AGENTS.md" "<!-- collab:agents-md:start -->"
assert_file_contains "$TMP/AGENTS.md" "<!-- collab:agents-md:end -->"
assert_file_contains "$TMP/AGENTS.md" "AI_AGENTS.md"

start_test "bootstrap into repo without AGENTS.md creates one with markers"
TMP2=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP2/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP2/templates"
(cd "$TMP2" && bash scripts/collab-init.sh) >/dev/null 2>&1
assert_file_exists "$TMP2/AGENTS.md"
assert_file_contains "$TMP2/AGENTS.md" "<!-- collab:agents-md:start -->"

start_test "re-init refreshes managed AGENTS.md content without touching unmanaged"
(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1
assert_file_contains "$TMP/AGENTS.md" "Custom section"
# Managed section should appear exactly once (not duplicated on re-run).
count=$(grep -c '<!-- collab:agents-md:start -->' "$TMP/AGENTS.md" || true)
assert_eq "1" "$count"

report
