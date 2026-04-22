#!/usr/bin/env bash
# Runs every tests/test-*.sh file in sequence.
set -uo pipefail

cd "$(dirname "$0")"
total_pass=0
total_fail=0
any_file_failed=0

for f in test-*.sh; do
  [[ -f "$f" ]] || continue
  echo "=== $f ==="
  if bash "$f"; then
    :
  else
    any_file_failed=1
  fi
done

echo
if [[ $any_file_failed -eq 0 ]]; then
  echo "ALL TEST FILES PASSED"
  exit 0
else
  echo "ONE OR MORE TEST FILES FAILED"
  exit 1
fi
