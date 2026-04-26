#!/usr/bin/env bash
# Verifies the 0.3.0 -> 0.4.0 migration: seed-only agent detection (with the
# calling agent excluded), non-interactive default-to-keep, INDEX cleanup.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
MIG="$SKILL_ROOT/scripts/migrations/0.3.0-to-0.4.0.sh"

# --- Setup: simulate a v0.3.0 multi-agent install with seed-only logs ---
TARGET=$(make_tmp_repo)
init_with_all_agents "$TARGET"
cd "$TARGET"

start_test "all three agents installed with seed-only work logs (precondition)"
[[ -f .collab/agents.d/claude.yml ]] && \
[[ -f .collab/agents.d/codex.yml ]]  && \
[[ -f .collab/agents.d/gemini.yml ]] && ok || fail "expected all three descriptors"

# --- Migration in non-interactive mode: caller=claude, others seed-only ---
start_test "migration in non-interactive mode keeps everyone (safety)"
out=$(COLLAB_AGENT=claude COLLAB_MIGRATE_NONINTERACTIVE=1 bash "$MIG" 2>&1)
echo "$out" | grep -q "non-interactive" && ok || fail "expected non-interactive notice: $out"

start_test "non-interactive migration leaves codex installed"
[[ -f .collab/agents.d/codex.yml && -f .codex/CODEX.md && -f docs/agents/codex.md ]] && ok || fail "codex partially removed"

start_test "non-interactive migration leaves gemini installed"
[[ -f .collab/agents.d/gemini.yml && -f GEMINI.md && -d .gemini/memory ]] && ok || fail "gemini partially removed"

start_test "migration excludes the caller from seed-only flagging"
out=$(COLLAB_AGENT=claude COLLAB_MIGRATE_NONINTERACTIVE=1 bash "$MIG" 2>&1)
echo "$out" | grep -E "^  - claude$" >/dev/null && fail "claude (the caller) should not be flagged" || ok

start_test "migration with no caller hint flags all seed-only agents"
out=$(unset COLLAB_AGENT; COLLAB_MIGRATE_NONINTERACTIVE=1 bash "$MIG" 2>&1)
for name in claude codex gemini; do
  echo "$out" | grep -qE "^  - $name$" || { fail "expected $name flagged: $out"; break; }
done
ok

# --- Exercise actual removal via COLLAB_MIGRATE_REMOVE_ALL_SEED ---
start_test "REMOVE_ALL_SEED=1 prunes flagged seed-only agents"
COLLAB_AGENT=claude COLLAB_MIGRATE_NONINTERACTIVE=1 COLLAB_MIGRATE_REMOVE_ALL_SEED=1 bash "$MIG" >/dev/null 2>&1
[[ ! -f .collab/agents.d/codex.yml && ! -f .codex/CODEX.md && ! -f docs/agents/codex.md ]] && ok || fail "codex artifacts not fully removed"

start_test "pruning strips matching INDEX rows"
grep -q "\.codex/" .collab/INDEX.md && fail "INDEX still mentions codex" || ok

start_test "pruning preserves the calling agent's artifacts"
[[ -f .collab/agents.d/claude.yml && -f .claude/CLAUDE.md ]] && ok || fail "claude was incorrectly pruned"

# --- Active agent (with real entry) is never flagged ---
TARGET2=$(make_tmp_repo)
init_with_all_agents "$TARGET2"
cd "$TARGET2"

# Append a real entry to codex log.
cat >> docs/agents/codex.md <<'EOF'

## 2026-04-25T10:00:00-05:00 — Real activity entry

Did some work.

### Task Receipt
Updates fanned out: docs/agents/codex.md
EOF

start_test "agents with real activity are not flagged for removal"
out=$(unset COLLAB_AGENT; COLLAB_MIGRATE_NONINTERACTIVE=1 bash "$MIG" 2>&1)
echo "$out" | grep -qE "^  - codex$" && fail "codex with real activity should not be flagged: $out" || ok

start_test "handoff blocks count as activity (not seed-only)"
TARGET3=$(make_tmp_repo)
init_with_all_agents "$TARGET3"
cd "$TARGET3"
bash "$SKILL_ROOT/scripts/collab-handoff.sh" gemini --from claude --message "test" >/dev/null 2>&1
out=$(unset COLLAB_AGENT; COLLAB_MIGRATE_NONINTERACTIVE=1 bash "$MIG" 2>&1)
# claude has a handoff block now → should not be flagged.
echo "$out" | grep -qE "^  - claude$" && fail "claude with handoff block should not be flagged: $out" || ok

cd "$SKILL_ROOT"
rm -rf "$TARGET" "$TARGET2" "$TARGET3"

report
