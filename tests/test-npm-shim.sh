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

report
