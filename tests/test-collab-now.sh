#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
NOW="$HERE/../scripts/collab-now.sh"

start_test "collab-now emits ISO 8601 with timezone offset"
out=$(bash "$NOW")
# Expect: YYYY-MM-DDTHH:MM:SS±HH:MM
if [[ "$out" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$ ]]; then
  ok
else
  fail "unexpected format: $out"
fi

start_test "collab-now outputs exactly one line"
lines=$(bash "$NOW" | wc -l)
assert_eq "1" "$(echo "$lines" | tr -d ' ')"

report
