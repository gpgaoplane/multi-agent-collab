#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
CLI="$SKILL_ROOT/bin/cli.js"

# Skip gracefully if node is unavailable.
if ! command -v node >/dev/null 2>&1; then
  echo "skip: node not found"
  report
  exit 0
fi

TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET"' EXIT

start_test "cli.js --help prints usage"
out=$(node "$CLI" --help 2>&1)
assert_contains "init" "$out"
assert_contains "join" "$out"

start_test "cli.js init bootstraps target repo"
(cd "$TARGET" && node "$CLI" init) >/dev/null 2>&1
assert_file_exists "$TARGET/AI_AGENTS.md"
assert_file_exists "$TARGET/AGENTS.md"
assert_file_exists "$TARGET/.collab/VERSION"

start_test "cli.js join <name> adds agent"
(cd "$TARGET" && node "$CLI" join aider) >/dev/null 2>&1
assert_file_exists "$TARGET/.aider/AIDER.md"
assert_file_contains "$TARGET/.collab/INDEX.md" ".aider/AIDER.md"

start_test "cli.js with unknown subcommand errors"
out=$( (cd "$TARGET" && node "$CLI" nonsense 2>&1) || true)
assert_contains "Usage" "$out"

start_test "cli.js join without name errors"
out=$( (cd "$TARGET" && node "$CLI" join 2>&1) || true)
assert_contains "missing" "$out"

start_test "cli.js presence start proxies to collab-presence.sh"
TARGET2=$(make_tmp_repo)
init_with_all_agents "$TARGET2" "$SKILL_ROOT"
cd "$TARGET2"
node "$SKILL_ROOT/bin/cli.js" presence start --agent claude --session test >/dev/null 2>&1
grep -q "| claude | test |" .collab/ACTIVE.md && ok || fail "presence start via cli.js didn't work"

start_test "cli.js handoff proxies to collab-handoff.sh"
node "$SKILL_ROOT/bin/cli.js" handoff codex --from claude --message "via npx" >/dev/null 2>&1
grep -q "Handoff → codex" docs/agents/claude.md && ok || fail "handoff via cli.js didn't write block"

start_test "cli.js catchup preview works"
out=$(node "$SKILL_ROOT/bin/cli.js" catchup preview --agent codex --handoff 2>&1)
echo "$out" | grep -q "via npx" && ok || fail "catchup via cli.js didn't surface handoff"

cd "$SKILL_ROOT"
rm -rf "$TARGET2"

# --- v0.4.2: cli.js forwards flags to bash for init/join/archive/register ---

# init --agent codex: should produce a codex-only install, no .claude/
TARGET3=$(make_tmp_repo)
start_test "v0.4.2: cli.js init forwards --agent flag (codex-only install)"
(cd "$TARGET3" && node "$CLI" init --agent codex) >/dev/null 2>&1
[[ -f "$TARGET3/.codex/CODEX.md" ]] && [[ ! -d "$TARGET3/.claude" ]] && ok || \
  fail "expected codex-only install via --agent: claude=$([[ -d $TARGET3/.claude ]] && echo yes || echo no), codex=$([[ -f $TARGET3/.codex/CODEX.md ]] && echo yes || echo no)"

# Bogus-flag forwarding test: if cli.js forwards, bash emits "Unknown arg"; if not, bash
# silently runs default init. Use a fresh repo (no .collab) so bash doesn't otherwise act.
TARGET4=$(make_tmp_repo)
start_test "v0.4.2: cli.js init forwards arbitrary flags (bogus flag rejected by bash)"
out=$( (cd "$TARGET4" && node "$CLI" init --bogus-flag-xyz 2>&1) || true)
echo "$out" | grep -q "Unknown arg: --bogus-flag-xyz" && ok || fail "bogus flag didn't reach bash; got: $out"

# init --dry-run: forwarded flag, AI_AGENTS.md should NOT be created.
TARGET5=$(make_tmp_repo)
start_test "v0.4.2: cli.js init forwards --dry-run flag (AI_AGENTS.md not written)"
(cd "$TARGET5" && node "$CLI" init --dry-run) >/dev/null 2>&1
[[ ! -f "$TARGET5/AI_AGENTS.md" ]] && ok || \
  fail "expected --dry-run to skip writing AI_AGENTS.md"

# register --type/--owner: flags should reach collab-register.sh
TARGET6=$(make_tmp_repo)
init_with_all_agents "$TARGET6" "$SKILL_ROOT"
cd "$TARGET6"
mkdir -p docs/manual
cat > docs/manual/note.md <<'EOF'
# Manual note

Hand-written content with no frontmatter.
EOF
start_test "v0.4.2: cli.js register forwards --type/--owner flags (INDEX row reflects them)"
node "$CLI" register docs/manual/note.md --type doc --owner claude >/dev/null 2>&1
# Group H: register --type/--owner sets the values in the INDEX.md row.
grep "docs/manual/note.md" .collab/INDEX.md | grep -q "doc" && \
  grep "docs/manual/note.md" .collab/INDEX.md | grep -q "claude" && ok || \
  fail "type/owner not in INDEX row: $(grep 'docs/manual/note.md' .collab/INDEX.md)"

# join codex --branch ... : extra flags after agent name should reach bash.
TARGET7=$(make_tmp_repo)
init_with_all_agents "$TARGET7" "$SKILL_ROOT"
cd "$TARGET7"
start_test "v0.4.2: cli.js join forwards extra flags (bogus flag rejected)"
out=$( (node "$CLI" join codex --bogus-extra-flag 2>&1) || true)
echo "$out" | grep -q "Unknown arg: --bogus-extra-flag" && ok || fail "join extra flag didn't reach bash; got: $out"

cd "$SKILL_ROOT"
rm -rf "$TARGET3" "$TARGET4" "$TARGET5" "$TARGET6" "$TARGET7"

report
