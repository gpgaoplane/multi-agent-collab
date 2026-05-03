#!/usr/bin/env bash
# v0.4.2 (G7): merge_replace_section emits a loud WARNING and returns 1 when
# marker blocks are malformed (duplicate start or end markers). Without this,
# the awk pass silently duplicates the body section content.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

source "$SKILL_ROOT/scripts/lib/merge.sh"

mktmpfile() {
  local f
  f=$(mktemp)
  cat > "$f"
  echo "$f"
}

# --- Healthy: single start + end pair → no warning, no return-1 ---
healthy=$(mktmpfile <<'EOF'
prelude

<!-- collab:demo:start -->
old content
<!-- collab:demo:end -->

postlude
EOF
)
trap 'rm -f "$healthy" "${dup_start:-}" "${dup_end:-}" "${missing_end:-}"' EXIT

start_test "G7: healthy block — merge_replace_section succeeds, no warning"
err=$(merge_replace_section "$healthy" "demo" "new content" 2>&1)
status=$?
[[ "$status" == "0" ]] && [[ -z "$err" ]] && ok || fail "expected silent success; status=$status err=$err"

start_test "G7: healthy block — body actually replaced"
grep -q "new content" "$healthy" && ! grep -q "old content" "$healthy" && ok || \
  fail "replacement didn't apply: $(cat $healthy)"

# --- Doubled start markers → warning + return 1, file unchanged ---
dup_start=$(mktmpfile <<'EOF'
prelude

<!-- collab:demo:start -->
content A
<!-- collab:demo:start -->
content B
<!-- collab:demo:end -->

postlude
EOF
)
dup_start_before=$(sha256sum "$dup_start" | awk '{print $1}')

start_test "G7: doubled start — warning emitted to stderr"
err=$(merge_replace_section "$dup_start" "demo" "should not apply" 2>&1)
status=$?
[[ "$status" != "0" ]] && echo "$err" | grep -qE "duplicate start markers" && ok || \
  fail "expected duplicate-start warning + non-zero exit; status=$status err=$err"

start_test "G7: doubled start — file unchanged after failed replace"
dup_start_after=$(sha256sum "$dup_start" | awk '{print $1}')
[[ "$dup_start_before" == "$dup_start_after" ]] && ok || fail "file was modified despite failure"

# --- Doubled end markers → warning + return 1, file unchanged ---
dup_end=$(mktmpfile <<'EOF'
prelude

<!-- collab:demo:start -->
content
<!-- collab:demo:end -->
stray
<!-- collab:demo:end -->

postlude
EOF
)
dup_end_before=$(sha256sum "$dup_end" | awk '{print $1}')

start_test "G7: doubled end — warning emitted to stderr"
err=$(merge_replace_section "$dup_end" "demo" "should not apply" 2>&1)
status=$?
[[ "$status" != "0" ]] && echo "$err" | grep -qE "duplicate end markers" && ok || \
  fail "expected duplicate-end warning + non-zero exit; status=$status err=$err"

start_test "G7: doubled end — file unchanged after failed replace"
dup_end_after=$(sha256sum "$dup_end" | awk '{print $1}')
[[ "$dup_end_before" == "$dup_end_after" ]] && ok || fail "file was modified despite failure"

# --- Missing end (regression check on existing missing-marker handling) ---
missing_end=$(mktmpfile <<'EOF'
<!-- collab:demo:start -->
content
no end marker here
EOF
)

start_test "G7: missing end — existing missing-marker warning preserved"
err=$(merge_replace_section "$missing_end" "demo" "should not apply" 2>&1)
status=$?
[[ "$status" != "0" ]] && echo "$err" | grep -q "markers for section 'demo' missing" && ok || \
  fail "regression on missing-marker case; status=$status err=$err"

report
