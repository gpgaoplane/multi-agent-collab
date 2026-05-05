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

# --- v0.4.4: rotation-advisory content-awareness (G2) ---
# Bug: collab-check.sh:137-145 advised rotation purely on `wc -l > threshold`,
# even when entry_count <= rotate_keep_recent (rotation would be a no-op).
# Fix: branch advisory text on entry count.
#
# Critical fixture note: the existing fixture above is INDEX-only with no
# .collab/agents.d/ or .collab/config.yml — check_rotation_threshold would
# silently return 0. Advisory tests need init_with_all_agents per the
# tests/test-collab-rotate-log.sh:38-44 pattern.

SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# Helper: build a log with N dated entries (each ~30-40 lines so we cross the
# threshold easily). Uses date-only headers to also exercise the v0.4.2 regex.
make_log_with_entries() {
  local log="$1"
  local count="$2"
  for i in $(seq 1 "$count"); do
    cat >> "$log" <<EOF

## 2026-04-$(printf '%02d' "$i") — Advisory test entry $i

Did some substantial work for entry $i to push line count over threshold.
This entry has multiple lines including a Files block and Receipt to ensure
each entry contributes ~20 lines to the log.

### Files
- src/foo$i.go
- src/bar$i.go

### Notes
- Detail line A
- Detail line B
- Detail line C

### Task Receipt
- docs/agents/claude.md ........... new entry $i
- src/foo$i.go .................... refactor
- src/bar$i.go .................... refactor
EOF
  done
}

set_threshold() {
  local repo="$1"
  local val="$2"
  sed -i "s/^rotate_at_lines:.*/rotate_at_lines: $val/" "$repo/.collab/config.yml"
}

set_keep_recent() {
  local repo="$1"
  local val="$2"
  if grep -q "^rotate_keep_recent:" "$repo/.collab/config.yml"; then
    sed -i "s/^rotate_keep_recent:.*/rotate_keep_recent: $val/" "$repo/.collab/config.yml"
  else
    echo "rotate_keep_recent: $val" >> "$repo/.collab/config.yml"
  fi
}

# Case 1: log over threshold, entries > keep_recent → original "Run: ..." advisory.
TMP_OVER=$(make_tmp_repo)
trap 'rm -rf "$TMP" "${TMP_OVER:-}" "${TMP_AT:-}" "${TMP_BELOW:-}" "${TMP_NOTH:-}" "${TMP_LEGACY:-}" "${TMP_INVALID:-}" "${TMP_REGEX:-}"' EXIT
init_with_all_agents "$TMP_OVER" "$SKILL_ROOT"
make_log_with_entries "$TMP_OVER/docs/agents/claude.md" 8
set_threshold "$TMP_OVER" 50
set_keep_recent "$TMP_OVER" 3

start_test "v0.4.4: original advisory when entries > keep_recent"
out_over=$( (cd "$TMP_OVER" && bash "$CHECK") 2>&1 || true)
# init_with_all_agents seeds codex/gemini logs (~64 lines) which also exceed
# threshold but have 0 entries — they fire alternative advisory. Filter to
# claude.md to assert the original-advisory branch specifically.
out_over_claude=$(echo "$out_over" | grep "claude.md" || true)
echo "$out_over_claude" | grep -q "Run: ./scripts/collab-rotate-log.sh claude" && ok || fail "expected original advisory for claude; got: $out_over_claude"

start_test "v0.4.4: claude's advisory does NOT include 'no-op' wording (entries > keep)"
echo "$out_over_claude" | grep -q "no-op" && fail "alternative advisory wrongly fired for claude: $out_over_claude" || ok

# Case 2: log over threshold, entries == keep_recent → alternative advisory.
TMP_AT=$(make_tmp_repo)
init_with_all_agents "$TMP_AT" "$SKILL_ROOT"
make_log_with_entries "$TMP_AT/docs/agents/claude.md" 3
set_threshold "$TMP_AT" 30
set_keep_recent "$TMP_AT" 3

start_test "v0.4.4: alternative advisory when entries == keep_recent"
out_at=$( (cd "$TMP_AT" && bash "$CHECK") 2>&1 || true)
echo "$out_at" | grep -q "Rotation would be a no-op" && ok || fail "expected alternative advisory; got: $out_at"

start_test "v0.4.4: alternative advisory mentions raising rotate_at_lines"
echo "$out_at" | grep -q "Consider raising rotate_at_lines" && ok || fail "missing config-tuning hint: $out_at"

start_test "v0.4.4: alternative advisory does NOT include 'Run: ./scripts/collab-rotate-log.sh'"
echo "$out_at" | grep -q "Run: ./scripts/collab-rotate-log.sh" && fail "original advisory wrongly fired: $out_at" || ok

# Case 3: log over threshold, entries < keep_recent (degenerate but possible) → alternative advisory.
TMP_BELOW=$(make_tmp_repo)
init_with_all_agents "$TMP_BELOW" "$SKILL_ROOT"
make_log_with_entries "$TMP_BELOW/docs/agents/claude.md" 2
set_threshold "$TMP_BELOW" 20
set_keep_recent "$TMP_BELOW" 3

start_test "v0.4.4: alternative advisory when entries < keep_recent"
out_below=$( (cd "$TMP_BELOW" && bash "$CHECK") 2>&1 || true)
echo "$out_below" | grep -q "Rotation would be a no-op" && ok || fail "expected alternative advisory; got: $out_below"

# Case 4: log under threshold → no advisory at all.
TMP_NOTH=$(make_tmp_repo)
init_with_all_agents "$TMP_NOTH" "$SKILL_ROOT"
make_log_with_entries "$TMP_NOTH/docs/agents/claude.md" 2
set_threshold "$TMP_NOTH" 5000
set_keep_recent "$TMP_NOTH" 3

start_test "v0.4.4: no rotation advisory when log under threshold"
out_noth=$( (cd "$TMP_NOTH" && bash "$CHECK") 2>&1 || true)
echo "$out_noth" | grep -q "advisory:.*lines" && fail "advisory wrongly fired below threshold: $out_noth" || ok

# Case 5: legacy config without rotate_keep_recent → default 3 used; alternative fires at 3 entries.
TMP_LEGACY=$(make_tmp_repo)
init_with_all_agents "$TMP_LEGACY" "$SKILL_ROOT"
make_log_with_entries "$TMP_LEGACY/docs/agents/claude.md" 3
set_threshold "$TMP_LEGACY" 30
# Strip rotate_keep_recent from config to simulate a legacy install.
sed -i '/^rotate_keep_recent:/d' "$TMP_LEGACY/.collab/config.yml"

start_test "v0.4.4: legacy config without rotate_keep_recent uses default 3"
out_legacy=$( (cd "$TMP_LEGACY" && bash "$CHECK") 2>&1 || true)
echo "$out_legacy" | grep -q "rotate_keep_recent=3" && \
  echo "$out_legacy" | grep -q "Rotation would be a no-op" && ok || \
  fail "expected default-3 alternative advisory; got: $out_legacy"

# Case 6: invalid (negative) rotate_keep_recent → default 3 fallback.
TMP_INVALID=$(make_tmp_repo)
init_with_all_agents "$TMP_INVALID" "$SKILL_ROOT"
make_log_with_entries "$TMP_INVALID/docs/agents/claude.md" 3
set_threshold "$TMP_INVALID" 30
set_keep_recent "$TMP_INVALID" "-5"

start_test "v0.4.4: negative rotate_keep_recent falls back to default 3"
out_inv=$( (cd "$TMP_INVALID" && bash "$CHECK") 2>&1 || true)
echo "$out_inv" | grep -q "rotate_keep_recent=3" && ok || fail "expected fallback to 3 for negative value; got: $out_inv"

# Case 7: regex alignment — the entry-counting regex literal MUST appear in BOTH
# scripts/collab-check.sh and scripts/collab-rotate-log.sh. Guards against
# silent desync if either file's regex is edited without updating the other.
start_test "v0.4.4: G2 advisory regex literal-equal to rotate-log regex"
ROTATE_REGEX_LIT='^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}([T ]|$)'
grep -F "$ROTATE_REGEX_LIT" "$SKILL_ROOT/scripts/collab-rotate-log.sh" >/dev/null && \
  grep -F "$ROTATE_REGEX_LIT" "$SKILL_ROOT/scripts/collab-check.sh" >/dev/null && ok || \
  fail "regex literal '$ROTATE_REGEX_LIT' not present in both rotate-log.sh and check.sh"

report
