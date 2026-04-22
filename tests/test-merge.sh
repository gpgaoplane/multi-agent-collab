#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/lib/merge.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FILE="$TMP/target.md"
cat > "$FILE" <<'EOF'
# Target

Unmanaged intro.

<!-- collab:rules:start -->
old rules
<!-- collab:rules:end -->

Unmanaged outro.
EOF

NEW_CONTENT=$'new rule 1\nnew rule 2'

start_test "merge_replace_section swaps managed content"
merge_replace_section "$FILE" "rules" "$NEW_CONTENT"
assert_file_contains "$FILE" "new rule 1"
assert_file_contains "$FILE" "new rule 2"

start_test "merge_replace_section preserves unmanaged outro"
assert_file_contains "$FILE" "Unmanaged outro."

start_test "merge_replace_section preserves unmanaged intro"
assert_file_contains "$FILE" "Unmanaged intro."

start_test "merge_replace_section removed old content"
if grep -qF "old rules" "$FILE"; then fail "old content still present"; else ok; fi

start_test "merge_has_section detects present marker"
merge_has_section "$FILE" "rules" && ok || fail "should detect rules section"

start_test "merge_has_section returns non-zero for missing marker"
if ! merge_has_section "$FILE" "nonexistent"; then ok; else fail "false positive"; fi

start_test "merge_replace_section on file without markers returns error"
cat > "$TMP/no-marker.md" <<'EOF'
No markers here.
EOF
if ! merge_replace_section "$TMP/no-marker.md" "rules" "content" 2>/dev/null; then
  ok
else
  fail "should have errored on missing marker"
fi

report
