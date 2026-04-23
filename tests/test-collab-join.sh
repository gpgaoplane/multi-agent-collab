#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP"' EXIT

cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"
(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1

# Case 1: --join on a shipped descriptor (claude already exists from fresh init).
start_test "--join on existing descriptor is idempotent"
(cd "$TMP" && bash scripts/collab-init.sh --join claude) >/dev/null 2>&1
assert_file_exists "$TMP/.claude/CLAUDE.md"

# Case 2: --join on an unknown agent renders generic descriptor.
start_test "--join on unknown agent creates descriptor via generic template"
(cd "$TMP" && bash scripts/collab-init.sh --join opencode) >/dev/null 2>&1
assert_file_exists "$TMP/.collab/agents.d/opencode.yml"
assert_file_contains "$TMP/.collab/agents.d/opencode.yml" "name: opencode"
assert_file_contains "$TMP/.collab/agents.d/opencode.yml" "display: Opencode"

# Case 3: --join generates adapter + memory + log for unknown agent.
start_test "--join unknown agent generates adapter at .<name>/"
assert_file_exists "$TMP/.opencode/OPENCODE.md"

start_test "--join unknown agent generates memory dir"
assert_file_exists "$TMP/.opencode/memory/state.md"

start_test "--join unknown agent generates work log"
assert_file_exists "$TMP/docs/agents/opencode.md"

start_test "--join unknown agent registers in INDEX"
assert_file_contains "$TMP/.collab/INDEX.md" ".opencode/OPENCODE.md"

# Case 4: --join on gemini uses the SHIPPED descriptor (root GEMINI.md), not generic.
# Fresh bootstrap already wrote .gemini/; this test applies to scenarios where the
# shipped descriptor was removed from agents.d and we expect re-joining to restore
# correct conventions via the shipped template, not the generic fallback.
rm -f "$TMP/.collab/agents.d/gemini.yml"
start_test "--join gemini re-uses shipped descriptor (root GEMINI.md convention)"
(cd "$TMP" && bash scripts/collab-init.sh --join gemini) >/dev/null 2>&1
assert_file_contains "$TMP/.collab/agents.d/gemini.yml" "adapter_path: GEMINI.md"

# Case 5: --add-agent (v0.1.0 flag) still errors on missing descriptor.
start_test "--add-agent (v0.1.0 flag) still errors on missing descriptor"
out=$( (cd "$TMP" && bash scripts/collab-init.sh --add-agent nevermet 2>&1) || true)
assert_contains "descriptor" "$out"

report
