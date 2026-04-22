#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
REGISTER="$HERE/../scripts/collab-register.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.collab"
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

# File Registry

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
<!-- collab:index:end -->
EOF

mkdir -p "$TMP/docs/agents"
cat > "$TMP/docs/agents/claude.md" <<'EOF'
---
status: active
type: work-log
owner: claude
last-updated: 2026-04-22T10:00:00-05:00
read-if: "x"
skip-if: "y"
---

# Claude log
EOF

start_test "register adds new file using frontmatter metadata"
(cd "$TMP" && bash "$REGISTER" "docs/agents/claude.md")
assert_file_contains "$INDEX" "docs/agents/claude.md"
assert_file_contains "$INDEX" "work-log"
assert_file_contains "$INDEX" "claude"

start_test "register refuses files without frontmatter"
echo "no frontmatter" > "$TMP/bare.md"
if (cd "$TMP" && bash "$REGISTER" "bare.md" 2>/dev/null); then
  fail "should have refused"
else
  ok
fi

start_test "register errors when INDEX missing"
rm "$INDEX"
if (cd "$TMP" && bash "$REGISTER" "docs/agents/claude.md" 2>/dev/null); then
  fail "should have errored on missing INDEX"
else
  ok
fi

report
