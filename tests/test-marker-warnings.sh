#!/usr/bin/env bash
# Tests for M1 (inline marker warnings) and M6 (customization guide).
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- M1: Marker warnings present in templates ---
WARNING="WARNING: framework-managed; edit OUTSIDE this block, not inside"

start_test "AI_AGENTS.md project-summary marker has warning"
sed -n '/collab:project-summary:start/,/collab:project-summary:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "AI_AGENTS.md onboarding marker has warning"
sed -n '/collab:onboarding:start/,/collab:onboarding:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "AI_AGENTS.md behavioral-rules marker has warning"
sed -n '/collab:behavioral-rules:start/,/collab:behavioral-rules:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "AI_AGENTS.md routing-pointer marker has warning"
sed -n '/collab:routing-pointer:start/,/collab:routing-pointer:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "AI_AGENTS.md agent-log-template marker has warning"
sed -n '/collab:agent-log-template:start/,/collab:agent-log-template:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "AGENTS.md agents-md marker has warning"
sed -n '/collab:agents-md:start/,/collab:agents-md:end/p' "$SKILL_ROOT/templates/AGENTS.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "AGENTS.md critical-rules marker has warning"
sed -n '/collab:critical-rules:start/,/collab:critical-rules:end/p' "$SKILL_ROOT/templates/AGENTS.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "work-log-seed log-archived-summary marker has warning"
sed -n '/collab:log-archived-summary:start/,/collab:log-archived-summary:end/p' "$SKILL_ROOT/templates/work-log-seed.md" | grep -qF "$WARNING" && ok || fail "warning missing"

start_test "ADAPTER.md platform-notes is NOT marker-warned (user-editable scope)"
sed -n '/collab:platform-notes:start/,/collab:platform-notes:end/p' "$SKILL_ROOT/templates/adapter/ADAPTER.md" | grep -qF "$WARNING" && fail "platform-notes is user-editable; should NOT have framework warning" || ok

# --- Warnings survive a fresh bootstrap ---
TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP" "${TMP2:-}"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"
(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1

start_test "fresh AI_AGENTS.md retains marker warnings"
grep -qF "$WARNING" "$TMP/AI_AGENTS.md" && ok || fail "warning lost on bootstrap"

start_test "fresh AGENTS.md retains marker warnings"
grep -qF "$WARNING" "$TMP/AGENTS.md" && ok || fail "warning lost in AGENTS.md on bootstrap"

start_test "fresh work log retains marker warning in archived-summary block"
grep -qF "$WARNING" "$TMP/docs/agents/claude.md" && ok || fail "warning lost in work log"

# --- Dynamic adapter table renderer includes the warning ---
start_test "dynamic current-adapters render includes the warning"
sed -n '/collab:current-adapters:start/,/collab:current-adapters:end/p' "$TMP/AI_AGENTS.md" | grep -qF "$WARNING" && ok || fail "dynamic render missing warning"

# --- Re-init preserves warnings (refreshes from template) ---
start_test "re-init preserves marker warnings"
(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1
grep -qF "$WARNING" "$TMP/AI_AGENTS.md" && ok || fail "warning lost on re-init"

# --- M6: Customization guide ---
start_test "AI_AGENTS.md template has customization-guide marker"
grep -q "<!-- collab:customization-guide:start -->" "$SKILL_ROOT/templates/AI_AGENTS.md" && ok || fail "customization-guide marker missing"

start_test "customization guide teaches edit-OUTSIDE-markers convention"
sed -n '/collab:customization-guide:start/,/collab:customization-guide:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -q "OUTSIDE markers" && ok || fail "edit-outside teaching missing from guide"

start_test "customization guide includes a code-block example"
sed -n '/collab:customization-guide:start/,/collab:customization-guide:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -q '^```markdown' && ok || fail "code-block example missing"

start_test "customization guide identifies user-owned no-marker files"
sed -n '/collab:customization-guide:start/,/collab:customization-guide:end/p' "$SKILL_ROOT/templates/AI_AGENTS.md" | grep -E "decisions|pitfalls|context" >/dev/null && ok || fail "user-owned no-marker files explanation missing"

start_test "fresh AI_AGENTS.md ships customization guide"
grep -q "<!-- collab:customization-guide:start -->" "$TMP/AI_AGENTS.md" && ok || fail "customization-guide missing in fresh install"

# --- Re-init injects customization-guide into stale AI_AGENTS.md ---
TMP2=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP2/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP2/templates"
(cd "$TMP2" && bash scripts/collab-init.sh) >/dev/null 2>&1
# Strip customization-guide to imitate v0.3.0-era install.
awk '/<!-- collab:customization-guide:start -->/,/<!-- collab:customization-guide:end -->/{next} {print}' "$TMP2/AI_AGENTS.md" > "$TMP2/AI_AGENTS.md.tmp"
mv "$TMP2/AI_AGENTS.md.tmp" "$TMP2/AI_AGENTS.md"
grep -q "customization-guide" "$TMP2/AI_AGENTS.md" && fail "precondition: customization-guide should be stripped" || true
# refresh_managed_sections only refreshes sections that ALREADY exist in target.
# For a brand-new section, we'd need an inject-on-missing path. AI_AGENTS.md
# refresh today doesn't auto-add missing sections (only AGENTS.md inject does).
# Document this: if customization-guide is missing, user must --force overwrite
# AI_AGENTS.md or manually paste the section. This test verifies current behavior.
(cd "$TMP2" && bash scripts/collab-init.sh) >/dev/null 2>&1
# Today: customization-guide stays missing on re-init unless --force is used.
# This is expected behavior for AI_AGENTS.md (refresh-only, no auto-inject).
start_test "re-init does NOT auto-add missing customization-guide to AI_AGENTS.md (refresh-only by design)"
grep -q "customization-guide" "$TMP2/AI_AGENTS.md" && fail "unexpected auto-add" || ok

report
