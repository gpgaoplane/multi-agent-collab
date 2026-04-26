#!/usr/bin/env bash
# Tests for collab-rotate-log.sh (Group B of v0.4.0).
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
ROTATE="$SKILL_ROOT/scripts/collab-rotate-log.sh"

# Helper: append N synthetic entries to a log. Each entry has Files/Notes
# subsections so we exercise the "## subsection inside entry" boundary case.
append_entries() {
  local log="$1"
  local count="$2"
  for i in $(seq 1 "$count"); do
    cat >> "$log" <<EOF

## 2026-04-$(printf '%02d' "$i")T10:00:00-05:00 — Test entry $i

Did some work for test $i.

### Files
- src/foo$i.go

### Notes
- internal heading must not split entry

### Task Receipt
Updates fanned out:
- docs/agents/claude.md ........... new entry $i
- src/foo$i.go .................... refactor

Missing / intentionally skipped: none
EOF
  done
}

# --- Setup: claude-only repo with 12 entries on the work log ---
TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP" "${TMP_CRLF:-}" "${TMP_BELOW:-}" "${TMP_HANDOFF:-}"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"
(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP/docs/agents/claude.md" 12

# --- Basic rotation ---
start_test "rotation archives entries beyond keep_recent"
(cd "$TMP" && bash scripts/collab-rotate-log.sh claude --threshold 100 --keep 4) >/dev/null 2>&1
live_entries=$(grep -cE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$TMP/docs/agents/claude.md")
assert_eq "4" "$live_entries"

start_test "rotation creates archive file with full content"
archive=$(ls "$TMP/.collab/archive/agents/"claude-*.md 2>/dev/null | head -1)
[[ -n "$archive" ]] && ok || fail "no archive file created"

start_test "archive contains all 8 archived entries verbatim"
arch_entries=$(grep -cE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$archive")
assert_eq "8" "$arch_entries"

start_test "archive file has frontmatter status: archived"
grep -q '^status: archived$' "$archive" && ok || fail "archive lacks archived status frontmatter"

start_test "live log has summary section with archived entry one-liners"
summary=$(awk '/<!-- collab:log-archived-summary:start -->/,/<!-- collab:log-archived-summary:end -->/' "$TMP/docs/agents/claude.md")
echo "$summary" | grep -q "2026-04-01" && echo "$summary" | grep -q "src/foo1.go" && ok || fail "summary missing entry 1: $summary"

start_test "summary preserves Receipt file references"
echo "$summary" | grep -q "docs/agents/claude.md" && ok || fail "summary lost receipt content"

start_test "rotation registers archive in INDEX"
grep -q "archive/agents/claude-" "$TMP/.collab/INDEX.md" && ok || fail "archive not registered"

# --- Idempotence ---
start_test "second rotation is a no-op (entries unchanged)"
before=$(wc -l < "$TMP/docs/agents/claude.md")
(cd "$TMP" && bash scripts/collab-rotate-log.sh claude --threshold 100 --keep 4) >/dev/null 2>&1
after=$(wc -l < "$TMP/docs/agents/claude.md")
assert_eq "$before" "$after"

start_test "second rotation does not duplicate summary lines"
new_summary=$(awk '/<!-- collab:log-archived-summary:start -->/,/<!-- collab:log-archived-summary:end -->/' "$TMP/docs/agents/claude.md")
new_count=$(echo "$new_summary" | grep -cE '^- 2026-04-')
# 8 archived entries; second run shouldn't duplicate them.
assert_eq "8" "$new_count"

# --- Subsection-inside-entry boundary case ---
start_test "## Files / ## Notes subsections inside an entry don't split it"
# Each archived entry retains its Files/Notes subsections in the archive file.
sub_count=$(grep -c '^### Files$' "$archive")
assert_eq "8" "$sub_count"

# --- CRLF fixture ---
TMP_CRLF=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_CRLF/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_CRLF/templates"
(cd "$TMP_CRLF" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_CRLF/docs/agents/claude.md" 12
# Convert log to CRLF.
awk '{printf "%s\r\n", $0}' "$TMP_CRLF/docs/agents/claude.md" > "$TMP_CRLF/docs/agents/claude.md.crlf"
mv "$TMP_CRLF/docs/agents/claude.md.crlf" "$TMP_CRLF/docs/agents/claude.md"

start_test "rotation handles CRLF logs without miscounting"
out=$( (cd "$TMP_CRLF" && bash scripts/collab-rotate-log.sh claude --threshold 100 --keep 4) 2>&1)
echo "$out" | grep -q "archived 8" && ok || fail "CRLF rotation failed: $out"

# --- Below-threshold no-op ---
TMP_BELOW=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_BELOW/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_BELOW/templates"
(cd "$TMP_BELOW" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_BELOW/docs/agents/claude.md" 2

start_test "below threshold: rotation is a no-op"
out=$( (cd "$TMP_BELOW" && bash scripts/collab-rotate-log.sh claude --threshold 1000 --keep 4) 2>&1)
echo "$out" | grep -q "nothing to do" && ok || fail "expected no-op: $out"

# --- Open handoff blocks preserved (not archived) ---
TMP_HANDOFF=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_HANDOFF/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_HANDOFF/templates"
(cd "$TMP_HANDOFF" && bash scripts/collab-init.sh) >/dev/null 2>&1
(cd "$TMP_HANDOFF" && bash scripts/collab-init.sh --join codex) >/dev/null 2>&1
append_entries "$TMP_HANDOFF/docs/agents/claude.md" 12
# Append an open handoff block at end-of-file (typical placement).
(cd "$TMP_HANDOFF" && bash scripts/collab-handoff.sh codex --from claude --message "open handoff to preserve" >/dev/null 2>&1)

start_test "rotation preserves open handoff blocks"
(cd "$TMP_HANDOFF" && bash scripts/collab-rotate-log.sh claude --threshold 100 --keep 4) >/dev/null 2>&1
grep -q '<!-- collab:handoff:start id=' "$TMP_HANDOFF/docs/agents/claude.md" && ok || fail "open handoff block lost"

start_test "rotation preserves handoff status: open"
grep -q "status.* open" "$TMP_HANDOFF/docs/agents/claude.md" && ok || fail "handoff status lost"

# --- collab-check warns when log exceeds threshold ---
TMP_CHECK=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_CHECK/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_CHECK/templates"
(cd "$TMP_CHECK" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_CHECK/docs/agents/claude.md" 12

start_test "collab-check advises rotation when log > rotate_at_lines"
# Override threshold to 50 so 12 entries clearly exceed.
sed -i 's/^rotate_at_lines:.*/rotate_at_lines: 50/' "$TMP_CHECK/.collab/config.yml"
out=$( (cd "$TMP_CHECK" && bash scripts/collab-check.sh) 2>&1)
echo "$out" | grep -q "advisory: docs/agents/claude.md" && echo "$out" | grep -q "collab-rotate-log.sh claude" && ok || fail "no rotation advisory: $out"

rm -rf "$TMP_CHECK"

report
