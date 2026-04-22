#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

start_test "assert_eq basic"
assert_eq "foo" "foo"

start_test "assert_contains basic"
assert_contains "world" "hello world"

start_test "assert_file_exists on this file"
assert_file_exists "$(dirname "$0")/harness.sh"

report
