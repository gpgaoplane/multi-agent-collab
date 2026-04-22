#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE="$HERE/../scripts/collab-archive.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.collab" "$TMP/docs"
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
| docs/old.md | design-doc | shared | active | 2026-04-22T00:00:00-05:00 |
<!-- collab:index:end -->
EOF

cat > "$TMP/docs/old.md" <<'EOF'
---
status: active
type: design-doc
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "x"
skip-if: "y"
---

# Old design
EOF

start_test "archive moves file to .collab/archive/"
(cd "$TMP" && bash "$ARCHIVE" "docs/old.md")
assert_file_exists "$TMP/.collab/archive/docs/old.md"

start_test "archive removes file from original location"
[[ ! -f "$TMP/docs/old.md" ]] && ok || fail "original still present"

start_test "archive updates INDEX row status to archived"
row=$(source "$HERE/../scripts/lib/index.sh"; idx_get_row "$INDEX" ".collab/archive/docs/old.md")
assert_contains "archived" "$row"

start_test "archived file's own frontmatter status is archived"
archived_status=$(source "$HERE/../scripts/lib/frontmatter.sh"; fm_get_field "$TMP/.collab/archive/docs/old.md" status)
assert_eq "archived" "$archived_status"

report
