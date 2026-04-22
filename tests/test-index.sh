#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/lib/index.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

INDEX="$TMP/INDEX.md"
cat > "$INDEX" <<'EOF'
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T10:00:00-05:00
read-if: "session start"
skip-if: "never"
---

# File Registry

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
| AI_AGENTS.md | shared | shared | active | 2026-04-22T09:00:00-05:00 |
<!-- collab:index:end -->
EOF

start_test "idx_get_row returns existing row"
row=$(idx_get_row "$INDEX" "AI_AGENTS.md")
assert_contains "shared" "$row"

start_test "idx_get_row returns empty for missing path"
row=$(idx_get_row "$INDEX" "nonexistent.md")
assert_eq "" "$row"

start_test "idx_upsert adds new row"
idx_upsert "$INDEX" "docs/agents/claude.md" "work-log" "claude" "active" "2026-04-22T10:15:00-05:00"
row=$(idx_get_row "$INDEX" "docs/agents/claude.md")
assert_contains "claude" "$row"
assert_contains "work-log" "$row"

start_test "idx_upsert updates existing row"
idx_upsert "$INDEX" "AI_AGENTS.md" "shared" "shared" "stale" "2026-04-22T11:00:00-05:00"
row=$(idx_get_row "$INDEX" "AI_AGENTS.md")
assert_contains "stale" "$row"

start_test "idx_list_paths returns all registered paths"
paths=$(idx_list_paths "$INDEX")
assert_contains "AI_AGENTS.md" "$paths"
assert_contains "docs/agents/claude.md" "$paths"

start_test "idx_remove deletes a row"
idx_remove "$INDEX" "AI_AGENTS.md"
row=$(idx_get_row "$INDEX" "AI_AGENTS.md")
assert_eq "" "$row"

report
