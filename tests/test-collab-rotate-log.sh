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

# --- v0.4.2: date-only entry headers must be detected ---
# Helper: append N entries with date-only headers (no T-time suffix).
append_date_only_entries() {
  local log="$1"
  local count="$2"
  for i in $(seq 1 "$count"); do
    cat >> "$log" <<EOF

## 2026-04-$(printf '%02d' "$i") — Date-only entry $i

Did some work for test $i with a date-only header.

### Files
- src/bar$i.go

### Task Receipt
- docs/agents/claude.md ........... new entry $i
EOF
  done
}

TMP_DATEONLY=$(make_tmp_repo)
trap 'rm -rf "$TMP" "${TMP_CRLF:-}" "${TMP_BELOW:-}" "${TMP_HANDOFF:-}" "${TMP_DATEONLY:-}" "${TMP_MIXED:-}" "${TMP_DEFAULT:-}"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TMP_DATEONLY/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_DATEONLY/templates"
(cd "$TMP_DATEONLY" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_date_only_entries "$TMP_DATEONLY/docs/agents/claude.md" 12

start_test "v0.4.2: date-only headers (## 2026-04-28 ...) detected by rotation"
out=$( (cd "$TMP_DATEONLY" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 4) 2>&1)
echo "$out" | grep -q "archived 8" && ok || fail "date-only rotation failed: $out"

start_test "v0.4.2: archived date-only entries appear in archive file"
archive_do=$(ls "$TMP_DATEONLY/.collab/archive/agents/"claude-*.md 2>/dev/null | head -1)
[[ -n "$archive_do" ]] && grep -q "Date-only entry 1" "$archive_do" && ok || fail "date-only entries missing from archive"

# --- v0.4.2: mixed date-only + datetime headers ---
TMP_MIXED=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_MIXED/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_MIXED/templates"
(cd "$TMP_MIXED" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_MIXED/docs/agents/claude.md" 6
append_date_only_entries "$TMP_MIXED/docs/agents/claude.md" 6

start_test "v0.4.2: mixed date-only + datetime headers both detected"
out=$( (cd "$TMP_MIXED" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 4) 2>&1)
echo "$out" | grep -q "archived 8" && ok || fail "mixed-format rotation failed: $out"

# --- v0.4.2: default rotate_keep_recent is 3 (no flag, no config override) ---
TMP_DEFAULT=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_DEFAULT/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_DEFAULT/templates"
(cd "$TMP_DEFAULT" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_DEFAULT/docs/agents/claude.md" 12

start_test "v0.4.2: default rotate_keep_recent is 3 (from shipped config)"
# Don't pass --keep; rely on config.yml (which now ships 3).
out=$( (cd "$TMP_DEFAULT" && bash scripts/collab-rotate-log.sh claude --threshold 50) 2>&1)
echo "$out" | grep -q "kept 3" && ok || fail "expected 'kept 3' from default config: $out"

start_test "v0.4.2: live log has 3 entries after default rotation"
live_after=$(grep -cE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}([T ]|$)' "$TMP_DEFAULT/docs/agents/claude.md")
assert_eq "3" "$live_after"

# --- v0.4.2: explicit config override still wins ---
TMP_OVERRIDE=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_OVERRIDE/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_OVERRIDE/templates"
(cd "$TMP_OVERRIDE" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_OVERRIDE/docs/agents/claude.md" 12
# Override config to keep 8 (simulating an existing v0.4.1 install).
sed -i 's/^rotate_keep_recent:.*/rotate_keep_recent: 8/' "$TMP_OVERRIDE/.collab/config.yml"

start_test "v0.4.2: explicit config rotate_keep_recent: 8 still honored"
out=$( (cd "$TMP_OVERRIDE" && bash scripts/collab-rotate-log.sh claude --threshold 50) 2>&1)
echo "$out" | grep -q "kept 8" && ok || fail "expected 'kept 8' from config override: $out"

rm -rf "$TMP_OVERRIDE"

# --- v0.4.4: same-day archive append (no clobber) ---
# Bug: scripts/collab-rotate-log.sh:142-154 wrote the archive with `> "$ARCHIVE_FILE"`
# (clobber). Filename is date-stamped, so a second rotation on the same day
# silently destroyed the prior archive's entry bodies. Fix: append to existing
# archive on same-day re-rotation; fresh-write only when file is absent.

# Setup: 12 entries; first rotate keep=8 (archives 1..4); second rotate keep=3
# (archives 5..9, appended to existing archive). Both on same calendar day.
TMP_APPEND=$(make_tmp_repo)
trap 'rm -rf "$TMP" "${TMP_CRLF:-}" "${TMP_BELOW:-}" "${TMP_HANDOFF:-}" "${TMP_DATEONLY:-}" "${TMP_MIXED:-}" "${TMP_DEFAULT:-}" "${TMP_APPEND:-}" "${TMP_NOFM:-}" "${TMP_DRY:-}" "${TMP_FRESH:-}"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TMP_APPEND/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_APPEND/templates"
(cd "$TMP_APPEND" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_APPEND/docs/agents/claude.md" 12

start_test "v0.4.4: first rotation writes fresh archive (regression check)"
out1=$( (cd "$TMP_APPEND" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 8) 2>&1)
echo "$out1" | grep -q "wrote 4 entries to fresh" && ok || fail "expected fresh-write stderr; got: $out1"

archive_app=$(ls "$TMP_APPEND/.collab/archive/agents/"claude-*.md 2>/dev/null | head -1)
[[ -n "$archive_app" ]] || fail "no archive after first rotation"

start_test "v0.4.4: archive after first rotation contains 4 entries"
first_count=$(grep -cE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$archive_app")
assert_eq "4" "$first_count"

start_test "v0.4.4: second rotation same day appends to existing archive (no clobber)"
out2=$( (cd "$TMP_APPEND" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 3) 2>&1)
echo "$out2" | grep -q "appended 5 entries to existing" && ok || fail "expected append stderr; got: $out2"

start_test "v0.4.4: archive after second rotation contains BOTH archived blocks (4+5=9 entries)"
second_count=$(grep -cE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$archive_app")
assert_eq "9" "$second_count"

start_test "v0.4.4: archive contains exactly one '### Continued — rotated' separator after one append"
cont_count=$(grep -cE '^### Continued — rotated ' "$archive_app")
assert_eq "1" "$cont_count"

start_test "v0.4.4: continuation marker is H3, not H2 (avoids ^## entry-counter inflation)"
h2_cont=$(grep -cE '^## Continued' "$archive_app" || true)
assert_eq "0" "$h2_cont"

start_test "v0.4.4: archive's original entries (1..4) still present after append"
grep -q "Test entry 1" "$archive_app" && grep -q "Test entry 4" "$archive_app" && ok || fail "first-rotation entries lost"

start_test "v0.4.4: archive's newly-appended entries (5..9) present"
grep -q "Test entry 5" "$archive_app" && grep -q "Test entry 9" "$archive_app" && ok || fail "second-rotation entries missing"

start_test "v0.4.4: terminal message says 'appended to' for the append case"
echo "$out2" | grep -q "archived 5 entries (appended to" && ok || fail "expected 'appended to' in terminal msg; got: $out2"

# --- v0.4.4: append to existing archive without frontmatter (warns but succeeds) ---
TMP_NOFM=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_NOFM/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_NOFM/templates"
(cd "$TMP_NOFM" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_NOFM/docs/agents/claude.md" 12
mkdir -p "$TMP_NOFM/.collab/archive/agents"
NOW_DATE_NOFM=$(date +%Y%m%d)
# Hand-craft an archive file with NO frontmatter — just a markdown body.
cat > "$TMP_NOFM/.collab/archive/agents/claude-${NOW_DATE_NOFM}.md" <<'EOF'
# Hand-edited archive (no frontmatter)

Some pre-existing content the user wrote manually.
EOF

start_test "v0.4.4: append to no-frontmatter archive emits stderr warning"
out3=$( (cd "$TMP_NOFM" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 4) 2>&1)
echo "$out3" | grep -q "WARNING.*has no frontmatter" && ok || fail "expected no-frontmatter warning; got: $out3"

start_test "v0.4.4: no-frontmatter archive still receives appended content"
grep -q "Hand-edited archive" "$TMP_NOFM/.collab/archive/agents/claude-${NOW_DATE_NOFM}.md" && \
  grep -q "Test entry 1" "$TMP_NOFM/.collab/archive/agents/claude-${NOW_DATE_NOFM}.md" && ok || \
  fail "expected pre-existing content + appended entries in no-fm archive"

# --- v0.4.4: --dry-run on existing archive does NOT mutate the archive ---
TMP_DRY=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_DRY/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_DRY/templates"
(cd "$TMP_DRY" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_DRY/docs/agents/claude.md" 12
# First rotation creates the archive.
(cd "$TMP_DRY" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 8) >/dev/null 2>&1
archive_dry=$(ls "$TMP_DRY/.collab/archive/agents/"claude-*.md 2>/dev/null | head -1)
archive_dry_sha_before=$(sha1sum "$archive_dry" 2>/dev/null | awk '{print $1}' || shasum "$archive_dry" | awk '{print $1}')

start_test "v0.4.4: --dry-run on existing archive leaves it byte-equivalent"
(cd "$TMP_DRY" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 3 --dry-run) >/dev/null 2>&1
archive_dry_sha_after=$(sha1sum "$archive_dry" 2>/dev/null | awk '{print $1}' || shasum "$archive_dry" | awk '{print $1}')
assert_eq "$archive_dry_sha_before" "$archive_dry_sha_after"

# --- v0.4.4: fresh-write path produces archive with frontmatter (regression check) ---
TMP_FRESH=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP_FRESH/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP_FRESH/templates"
(cd "$TMP_FRESH" && bash scripts/collab-init.sh) >/dev/null 2>&1
append_entries "$TMP_FRESH/docs/agents/claude.md" 12

start_test "v0.4.4: first rotation produces archive with status: archived frontmatter"
(cd "$TMP_FRESH" && bash scripts/collab-rotate-log.sh claude --threshold 50 --keep 4) >/dev/null 2>&1
archive_fresh=$(ls "$TMP_FRESH/.collab/archive/agents/"claude-*.md 2>/dev/null | head -1)
head -1 "$archive_fresh" | grep -q '^---$' && grep -q '^status: archived$' "$archive_fresh" && ok || \
  fail "fresh-write archive missing frontmatter"

start_test "v0.4.4: first rotation archive has NO continuation marker"
zero_cont=$(grep -cE '^### Continued — rotated ' "$archive_fresh" || true)
assert_eq "0" "$zero_cont"

report
