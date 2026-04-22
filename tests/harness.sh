#!/usr/bin/env bash
# Shared test utilities for multi-agent-collab.
# Sourced by every tests/test-*.sh file.

set -uo pipefail

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
