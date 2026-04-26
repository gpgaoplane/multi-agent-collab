#!/usr/bin/env bash
# Tests for Group H: collab-register --type/--owner (H1) and collab-check --stats (H2).
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Setup ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"
init_with_all_agents "$TARGET" "$SKILL_ROOT"

# --- H1: register a file lacking frontmatter, with flags ---
cat > "$TARGET/docs/external-log.md" <<'EOF'
# External tooling log

This file has no frontmatter (e.g. produced by a non-collab tool).
EOF

start_test "register without frontmatter and without flags errors"
out=$( (cd "$TARGET" && bash scripts/collab-register.sh docs/external-log.md) 2>&1)
rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -q "no frontmatter" && ok || fail "expected error: rc=$rc out=$out"

start_test "register --type --owner registers a file lacking frontmatter"
out=$( (cd "$TARGET" && bash scripts/collab-register.sh docs/external-log.md --type log --owner external) 2>&1)
rc=$?
[[ $rc -eq 0 ]] && echo "$out" | grep -q "Registered" && ok || fail "register failed: rc=$rc out=$out"

start_test "registered row reflects --type"
grep -q "docs/external-log.md.*log" "$TARGET/.collab/INDEX.md" && ok || fail "type not in INDEX"

start_test "registered row reflects --owner"
grep -q "docs/external-log.md.*external" "$TARGET/.collab/INDEX.md" && ok || fail "owner not in INDEX"

start_test "register --status overrides default 'active'"
echo "stale-only" > "$TARGET/docs/stale-tool.md"
(cd "$TARGET" && bash scripts/collab-register.sh docs/stale-tool.md --type log --owner external --status stale) >/dev/null 2>&1
grep -q "docs/stale-tool.md.*stale" "$TARGET/.collab/INDEX.md" && ok || fail "status override missing"

start_test "register flags override frontmatter values when both are present"
# AI_AGENTS.md has frontmatter with type=shared, owner=shared. Override with flags.
(cd "$TARGET" && bash scripts/collab-register.sh AI_AGENTS.md --type custom-type --owner custom-owner) >/dev/null 2>&1
grep -q "AI_AGENTS.md.*custom-type.*custom-owner" "$TARGET/.collab/INDEX.md" && ok || fail "flag override of frontmatter values failed"

# Reset AI_AGENTS.md row back to its frontmatter values for clean later assertions.
(cd "$TARGET" && bash scripts/collab-register.sh AI_AGENTS.md) >/dev/null 2>&1

start_test "register --type only (frontmatter supplies the rest) works"
echo "partial" > "$TARGET/docs/partial-meta.md"
(cd "$TARGET" && bash scripts/collab-register.sh docs/partial-meta.md --type custom-type --owner team) >/dev/null 2>&1
grep -q "docs/partial-meta.md.*custom-type.*team" "$TARGET/.collab/INDEX.md" && ok || fail "partial flag set failed"

start_test "register unknown flag errors clearly"
out=$( (cd "$TARGET" && bash scripts/collab-register.sh docs/external-log.md --bogus value) 2>&1)
rc=$?
[[ $rc -ne 0 ]] && echo "$out" | grep -q "unknown flag" && ok || fail "expected unknown-flag error: rc=$rc out=$out"

# --- H2: collab-check --stats ---
start_test "collab-check --stats prints a stats header"
out=$( (cd "$TARGET" && bash scripts/collab-check.sh --stats) 2>&1)
echo "$out" | grep -q "collab-check stats" && ok || fail "stats header missing"

start_test "collab-check --stats prints columns: agent / entries / log lines / open handoff / archives"
echo "$out" | head -3 | grep -q "agent.*entries.*log lines.*open handoff.*archives" && ok || fail "stats columns missing"

start_test "collab-check --stats lists each installed agent"
for a in claude codex gemini; do
  echo "$out" | grep -qE "^${a}\b" || { fail "stats row for $a missing"; break; }
done
echo "$out" | grep -q "claude" && echo "$out" | grep -q "codex" && echo "$out" | grep -q "gemini" && ok

# Add a real entry to claude.md and verify entry count changes.
cat >> "$TARGET/docs/agents/claude.md" <<'EOF'

## 2026-04-26T10:00:00-05:00 — Stats test entry

Did some work.

### Task Receipt
Updates fanned out: docs/agents/claude.md
EOF

start_test "collab-check --stats reports the new claude entry"
out2=$( (cd "$TARGET" && bash scripts/collab-check.sh --stats) 2>&1)
# claude row should have entries >= 1
echo "$out2" | grep -E "^claude\s+1\s" >/dev/null && ok || fail "claude entry count not 1: $(echo "$out2" | grep claude)"

# Open handoff: write one and confirm stats report it.
(cd "$TARGET" && bash scripts/collab-handoff.sh codex --from claude --message "stats test") >/dev/null 2>&1
out3=$( (cd "$TARGET" && bash scripts/collab-check.sh --stats) 2>&1)

start_test "collab-check --stats reports open handoff count"
# claude row's open-handoff column should be >= 1
echo "$out3" | awk '/^claude/ {print $4}' | grep -q '^[1-9]' && ok || fail "open handoff count missing for claude: $(echo "$out3" | grep claude)"

start_test "collab-check --stats prints total INDEX entry count"
echo "$out3" | grep -q "INDEX entries (total managed files):" && ok || fail "INDEX total missing"

start_test "collab-check (no flag) still runs the audit and skips stats"
out4=$( (cd "$TARGET" && bash scripts/collab-check.sh) 2>&1)
echo "$out4" | grep -q "collab-check stats" && fail "stats leaked into normal mode" || ok

report
