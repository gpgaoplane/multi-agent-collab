#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP"' EXIT

# Link scripts and templates into the tmp repo so collab-init finds them.
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

(cd "$TMP" && bash scripts/collab-init.sh)

start_test "fresh bootstrap creates AI_AGENTS.md"
assert_file_exists "$TMP/AI_AGENTS.md"

start_test "fresh bootstrap creates .collab/ state files"
assert_file_exists "$TMP/.collab/VERSION"
assert_file_exists "$TMP/.collab/ACTIVE.md"
assert_file_exists "$TMP/.collab/INDEX.md"
assert_file_exists "$TMP/.collab/ROUTING.md"
assert_file_exists "$TMP/.collab/PROTOCOL.md"

start_test "fresh bootstrap creates descriptors"
assert_file_exists "$TMP/.collab/agents.d/claude.yml"
assert_file_exists "$TMP/.collab/agents.d/codex.yml"
assert_file_exists "$TMP/.collab/agents.d/gemini.yml"

start_test "fresh bootstrap creates Claude adapter + memory"
assert_file_exists "$TMP/.claude/CLAUDE.md"
assert_file_exists "$TMP/.claude/memory/state.md"
assert_file_exists "$TMP/.claude/memory/context.md"
assert_file_exists "$TMP/.claude/memory/decisions.md"
assert_file_exists "$TMP/.claude/memory/pitfalls.md"

start_test "fresh bootstrap creates Codex adapter + memory"
assert_file_exists "$TMP/.codex/CODEX.md"
assert_file_exists "$TMP/.codex/memory/state.md"

start_test "fresh bootstrap creates Gemini root adapter + memory"
assert_file_exists "$TMP/GEMINI.md"
assert_file_exists "$TMP/.gemini/memory/state.md"

start_test "fresh bootstrap creates work logs"
assert_file_exists "$TMP/docs/agents/claude.md"
assert_file_exists "$TMP/docs/agents/codex.md"
assert_file_exists "$TMP/docs/agents/gemini.md"

start_test "fresh bootstrap substitutes placeholder tokens"
# AGENT_DISPLAY should be substituted; no {{ remaining in claude's adapter.
if grep -qF "{{" "$TMP/.claude/CLAUDE.md"; then
  fail "unreplaced template tokens in .claude/CLAUDE.md"
else
  ok
fi

start_test "fresh bootstrap registers files in INDEX"
idx_lines=$(grep -c '^|' "$TMP/.collab/INDEX.md" || true)
# Expect: header + separator + >= 10 registered files.
[[ $idx_lines -ge 12 ]] && ok || fail "only $idx_lines INDEX rows; expected >= 12"

start_test "collab-check passes on a fresh bootstrap"
(cd "$TMP" && bash scripts/collab-check.sh) && ok || fail "collab-check reported mismatches"

report
