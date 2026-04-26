#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Case 1: claude-only fresh install (default via COLLAB_AGENT=claude) ---
TMP=$(make_tmp_repo)

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

start_test "fresh bootstrap seeds ONLY the calling agent's descriptor"
assert_file_exists "$TMP/.collab/agents.d/claude.yml"
[[ ! -f "$TMP/.collab/agents.d/codex.yml" ]] && ok || fail "unexpected codex.yml on claude-only init"
[[ ! -f "$TMP/.collab/agents.d/gemini.yml" ]] && ok || fail "unexpected gemini.yml on claude-only init"

start_test "fresh bootstrap creates Claude adapter + memory"
assert_file_exists "$TMP/.claude/CLAUDE.md"
assert_file_exists "$TMP/.claude/memory/state.md"
assert_file_exists "$TMP/.claude/memory/context.md"
assert_file_exists "$TMP/.claude/memory/decisions.md"
assert_file_exists "$TMP/.claude/memory/pitfalls.md"

start_test "fresh bootstrap does NOT create other agents' adapter dirs"
[[ ! -d "$TMP/.codex" ]] && ok || fail "unexpected .codex/ on claude-only init"
[[ ! -d "$TMP/.gemini" ]] && ok || fail "unexpected .gemini/ on claude-only init"
[[ ! -f "$TMP/GEMINI.md" ]] && ok || fail "unexpected GEMINI.md on claude-only init"

start_test "fresh bootstrap creates only claude work log"
assert_file_exists "$TMP/docs/agents/claude.md"
[[ ! -f "$TMP/docs/agents/codex.md" ]] && ok || fail "unexpected codex work log"
[[ ! -f "$TMP/docs/agents/gemini.md" ]] && ok || fail "unexpected gemini work log"

start_test "fresh bootstrap substitutes placeholder tokens"
if grep -qF "{{" "$TMP/.claude/CLAUDE.md"; then
  fail "unreplaced template tokens in .claude/CLAUDE.md"
else
  ok
fi

start_test "fresh bootstrap registers files in INDEX"
idx_lines=$(grep -c '^|' "$TMP/.collab/INDEX.md" || true)
# Header + separator + >= 8 registered files (one agent's worth).
[[ $idx_lines -ge 10 ]] && ok || fail "only $idx_lines INDEX rows; expected >= 10"

start_test "collab-check passes on a fresh bootstrap"
(cd "$TMP" && bash scripts/collab-check.sh) && ok || fail "collab-check reported mismatches"

rm -rf "$TMP"

# --- Case 2: codex-only fresh install via --agent flag ---
TMP=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

# Override the harness default of claude.
(cd "$TMP" && COLLAB_AGENT="" bash scripts/collab-init.sh --agent codex) >/dev/null 2>&1

start_test "--agent codex fresh install seeds only codex"
assert_file_exists "$TMP/.collab/agents.d/codex.yml"
[[ ! -f "$TMP/.collab/agents.d/claude.yml" ]] && ok || fail "unexpected claude.yml"
assert_file_exists "$TMP/.codex/CODEX.md"
[[ ! -d "$TMP/.claude" ]] && ok || fail "unexpected .claude/"

rm -rf "$TMP"

# --- Case 3: gemini-only fresh install via --agent flag ---
TMP=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

(cd "$TMP" && COLLAB_AGENT="" bash scripts/collab-init.sh --agent gemini) >/dev/null 2>&1

start_test "--agent gemini fresh install seeds gemini with root GEMINI.md"
assert_file_exists "$TMP/.collab/agents.d/gemini.yml"
assert_file_exists "$TMP/GEMINI.md"
[[ ! -d "$TMP/.claude" ]] && ok || fail "unexpected .claude/"
[[ ! -d "$TMP/.codex" ]] && ok || fail "unexpected .codex/"

rm -rf "$TMP"

# --- Case 4: hard-fail when no agent can be detected ---
TMP=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

start_test "fresh init hard-fails with no detection signal and no --agent"
out=$( cd "$TMP" && unset COLLAB_AGENT CLAUDECODE CLAUDE_CODE_SSE_PORT CLAUDE_CODE_OAUTH_TOKEN CODEX_HOME CODEX_CLI GEMINI_CLI GEMINI_API_KEY GOOGLE_AI_API_KEY; bash scripts/collab-init.sh 2>&1 )
rc=$?
if [[ $rc -ne 0 ]] && echo "$out" | grep -q "cannot detect calling agent"; then
  ok
else
  fail "expected hard-fail, got rc=$rc out=$out"
fi

start_test "hard-fail leaves repo clean (no .collab/ or AI_AGENTS.md created)"
[[ ! -d "$TMP/.collab" ]] && ok || fail ".collab/ created despite hard-fail"
[[ ! -f "$TMP/AI_AGENTS.md" ]] && ok || fail "AI_AGENTS.md created despite hard-fail"

rm -rf "$TMP"

# --- Case 5: --join is rejected on fresh install ---
TMP=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

start_test "--join on fresh install errors with guidance"
out=$( (cd "$TMP" && bash scripts/collab-init.sh --join codex 2>&1) || true)
assert_contains "not valid on a fresh install" "$out"

rm -rf "$TMP"

# --- Case 6: join after fresh install adds the agent ---
TMP=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1
(cd "$TMP" && bash scripts/collab-init.sh --join codex) >/dev/null 2>&1

start_test "join codex after claude-only init creates codex artifacts"
assert_file_exists "$TMP/.collab/agents.d/codex.yml"
assert_file_exists "$TMP/.codex/CODEX.md"
assert_file_exists "$TMP/docs/agents/codex.md"

# --- A6: dynamic adapter table reflects installed agents ---
start_test "current-adapters table has exactly 1 agent row after claude-only init"
TMP2=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$TMP2/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP2/templates"
(cd "$TMP2" && bash scripts/collab-init.sh) >/dev/null 2>&1
# Data rows contain a backtick-wrapped log path "docs/agents/<name>.md`"; the
# table header doesn't, so count those to avoid matching the header row.
rows=$(awk '/<!-- collab:current-adapters:start -->/,/<!-- collab:current-adapters:end -->/' "$TMP2/AI_AGENTS.md" | grep -c 'docs/agents/' || true)
assert_eq "1" "$rows" "claude-only init should produce 1 adapter row"

start_test "current-adapters table grows to 2 rows after --join codex"
(cd "$TMP2" && bash scripts/collab-init.sh --join codex) >/dev/null 2>&1
rows=$(awk '/<!-- collab:current-adapters:start -->/,/<!-- collab:current-adapters:end -->/' "$TMP2/AI_AGENTS.md" | grep -c 'docs/agents/' || true)
assert_eq "2" "$rows" "after --join codex, expected 2 rows"

start_test "current-adapters lists Gemini with (root) annotation"
(cd "$TMP2" && bash scripts/collab-init.sh --join gemini) >/dev/null 2>&1
grep -q "GEMINI.md\` (root)" "$TMP2/AI_AGENTS.md" && ok || fail "Gemini row should annotate root convention"

rm -rf "$TMP" "$TMP2"

report
