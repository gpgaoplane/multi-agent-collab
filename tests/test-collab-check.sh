#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../scripts/collab-check.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.collab" "$TMP/docs/agents"

INDEX="$TMP/.collab/INDEX.md"
cat > "$INDEX" <<'EOF'
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "always"
skip-if: "never"
---

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
| docs/agents/claude.md | work-log | claude | active | 2026-04-22T00:00:00-05:00 |
| docs/agents/missing.md | work-log | ghost | active | 2026-04-22T00:00:00-05:00 |
<!-- collab:index:end -->
EOF

cat > "$TMP/docs/agents/claude.md" <<'EOF'
---
status: active
type: work-log
owner: claude
last-updated: 2026-04-22T00:00:00-05:00
read-if: "x"
skip-if: "y"
---

# log
EOF

# File exists on disk but NOT in INDEX:
cat > "$TMP/docs/agents/orphan.md" <<'EOF'
---
status: active
type: work-log
owner: orphan
last-updated: 2026-04-22T00:00:00-05:00
read-if: "x"
skip-if: "y"
---
EOF

start_test "check reports missing file (in INDEX, not on disk)"
out=$(cd "$TMP" && bash "$CHECK" 2>&1 || true)
assert_contains "missing.md" "$out"

start_test "check reports orphan file (on disk, not in INDEX)"
assert_contains "orphan.md" "$out"

start_test "check does not flag healthy file"
if [[ "$out" == *"claude.md (ok)"* || ! "$out" == *"claude.md (missing)"* ]]; then ok; else fail "claude.md wrongly flagged"; fi

start_test "check exits non-zero when mismatches exist"
(cd "$TMP" && bash "$CHECK" >/dev/null 2>&1) && fail "should have exited non-zero" || ok

report
