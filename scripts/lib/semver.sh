#!/usr/bin/env bash
# Numeric three-part semver compare helpers.
# Inputs MUST be valid semver X.Y.Z (detect_mode validates installed
# in collab-init.sh; shipped is controlled).
#
# Lex compare (e.g. "0.10.0" vs "0.9.0") sorts WRONG; these functions
# normalize each component to base-10 before numeric comparison.
#
# Provides:
#   version_le <a> <b>   — returns 0 if a <= b, else 1
#   version_lt <a> <b>   — returns 0 if a <  b, else 1
#   version_eq <a> <b>   — returns 0 if a == b, else 1

version_le() {
  local a="$1" b="$2"
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$a"
  IFS=. read -r b1 b2 b3 <<< "$b"
  if (( 10#$a1 < 10#$b1 )); then return 0; fi
  if (( 10#$a1 > 10#$b1 )); then return 1; fi
  if (( 10#$a2 < 10#$b2 )); then return 0; fi
  if (( 10#$a2 > 10#$b2 )); then return 1; fi
  if (( 10#$a3 <= 10#$b3 )); then return 0; fi
  return 1
}

version_lt() {
  # a < b iff !(b <= a)
  ! version_le "$2" "$1"
}

version_eq() {
  [[ "$1" == "$2" ]]
}
