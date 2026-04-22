#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/lib/frontmatter.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/a.md" <<'EOF'
---
status: active
type: work-log
owner: claude
last-updated: 2026-04-22T10:15:30-05:00
---

# Body content
Some body text.
EOF

start_test "fm_get_field reads status"
assert_eq "active" "$(fm_get_field "$TMP/a.md" status)"

start_test "fm_get_field reads multi-word timestamp"
assert_eq "2026-04-22T10:15:30-05:00" "$(fm_get_field "$TMP/a.md" last-updated)"

start_test "fm_get_field missing field returns empty"
assert_eq "" "$(fm_get_field "$TMP/a.md" nonexistent)"

start_test "fm_has_frontmatter detects frontmatter"
fm_has_frontmatter "$TMP/a.md" && ok || fail "frontmatter not detected"

cat > "$TMP/b.md" <<'EOF'
No frontmatter here.
EOF

start_test "fm_has_frontmatter rejects file without frontmatter"
if ! fm_has_frontmatter "$TMP/b.md"; then ok; else fail "false positive"; fi

start_test "fm_set_field updates existing field"
fm_set_field "$TMP/a.md" status stale
assert_eq "stale" "$(fm_get_field "$TMP/a.md" status)"

start_test "fm_set_field preserves body"
assert_file_contains "$TMP/a.md" "Some body text."

start_test "fm_set_field adds missing field"
fm_set_field "$TMP/a.md" new-field "hello"
assert_eq "hello" "$(fm_get_field "$TMP/a.md" new-field)"

report
