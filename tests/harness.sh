#!/usr/bin/env bash
# Shared test utilities for multi-agent-collab.
# Sourced by every tests/test-*.sh file.

set -uo pipefail

# v0.4.0: collab-init hard-fails when no calling agent is detectable. Tests
# default to claude unless they specifically exercise other detection paths.
export COLLAB_AGENT="${COLLAB_AGENT:-claude}"

PASS=0
FAIL=0
CURRENT_TEST=""

ok() {
  ((++PASS))
  return 0
}

fail() {
  ((++FAIL))
  echo "  FAIL: ${CURRENT_TEST:-unnamed} — $1" >&2
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-values differ}"
  if [[ "$expected" == "$actual" ]]; then
    ok
  else
    fail "$msg: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="${3:-substring missing}"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok
  else
    fail "$msg: '$needle' not found in output"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "$path" ]] && ok || fail "file missing: $path"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if [[ -f "$path" ]] && grep -qF "$needle" "$path"; then
    ok
  else
    fail "file $path missing substring: $needle"
  fi
}

start_test() {
  CURRENT_TEST="$1"
}

report() {
  echo
  echo "Tests: PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
}

make_tmp_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  echo "$dir"
}

# Resolve the skill root once at source time (before tests cd into tmp dirs).
# BASH_SOURCE[0] is "tests/harness.sh" relative to the original cwd; once a test
# changes directory, this becomes unresolvable, so cache the absolute path now.
HARNESS_SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# init_with_all_agents <repo-dir> [<skill-root>]
# Bootstraps a repo with all three first-class agents installed. Used by tests
# that exercise multi-agent state (handoff, catchup, presence, etc.). For tests
# that just need a single-agent baseline, call collab-init.sh directly — the
# COLLAB_AGENT=claude default in this harness covers them.
init_with_all_agents() {
  local repo="$1"
  local skill_root="${2:-$HARNESS_SKILL_ROOT}"
  (cd "$repo" && bash "$skill_root/scripts/collab-init.sh") >/dev/null 2>&1
  (cd "$repo" && bash "$skill_root/scripts/collab-init.sh" --join codex) >/dev/null 2>&1
  (cd "$repo" && bash "$skill_root/scripts/collab-init.sh" --join gemini) >/dev/null 2>&1
}
