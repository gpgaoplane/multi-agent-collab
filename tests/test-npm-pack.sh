#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# Skip gracefully if npm is unavailable.
if ! command -v npm >/dev/null 2>&1; then
  echo "skip: npm not found"
  report
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Build tarball.
(cd "$SKILL_ROOT" && npm pack --pack-destination "$TMP" >/dev/null 2>&1)
TARBALL=$(ls "$TMP"/*.tgz 2>/dev/null | head -1)

# Dump listing once. Avoid `tar | grep -q` — grep -q closes the pipe early,
# SIGPIPE kills tar, and pipefail reports the pipeline as failed.
LISTING="$TMP/listing.txt"
if [[ -f "$TARBALL" ]]; then
  tar tzf "$TARBALL" > "$LISTING" 2>/dev/null
fi

start_test "npm pack produced a tarball"
[[ -f "$TARBALL" ]] && ok || fail "tarball not found in $TMP"

start_test "tarball contains scripts/collab-init.sh"
grep -qF "package/scripts/collab-init.sh" "$LISTING" && ok || fail "scripts missing from tarball"

start_test "tarball contains templates/AGENTS.md"
grep -qF "package/templates/AGENTS.md" "$LISTING" && ok || fail "AGENTS.md template missing"

start_test "tarball contains templates/agents.d/_generic.yml"
grep -qF "package/templates/agents.d/_generic.yml" "$LISTING" && ok || fail "generic descriptor template missing"

start_test "tarball contains bin/cli.js"
grep -qF "package/bin/cli.js" "$LISTING" && ok || fail "cli.js missing"

start_test "tarball contains SKILL.md"
grep -qF "package/SKILL.md" "$LISTING" && ok || fail "SKILL.md missing"

start_test "tarball contains scripts/migrations/0.1.0-to-0.2.0.sh"
grep -qF "package/scripts/migrations/0.1.0-to-0.2.0.sh" "$LISTING" && ok || fail "migration missing"

# Install tarball into a fresh npm root and test invocation.
NPM_ROOT="$TMP/npm-root"
mkdir -p "$NPM_ROOT"
(cd "$NPM_ROOT" && npm init -y >/dev/null 2>&1 && npm install "$TARBALL" >/dev/null 2>&1)

start_test "installed package exposes multi-agent-collab bin"
BIN="$NPM_ROOT/node_modules/.bin/multi-agent-collab"
[[ -f "$BIN" || -f "$BIN.cmd" ]] && ok || fail "bin not found at $BIN"

CLI_IN_PKG="$NPM_ROOT/node_modules/@gpgaoplane/multi-agent-collab/bin/cli.js"

start_test "installed package's cli.js exists"
assert_file_exists "$CLI_IN_PKG"

start_test "installed bin's init produces bootstrap"
TARGET=$(make_tmp_repo)
(cd "$TARGET" && node "$CLI_IN_PKG" init) >/dev/null 2>&1
assert_file_exists "$TARGET/AI_AGENTS.md"
assert_file_exists "$TARGET/AGENTS.md"
assert_file_exists "$TARGET/.collab/VERSION"
rm -rf "$TARGET"

report
