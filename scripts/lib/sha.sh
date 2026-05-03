#!/usr/bin/env bash
# Portable SHA-256 helper. Used by the migration sentinel system to detect
# when a migration script body has changed (so a future patch to a migration
# can re-trigger application without manual sentinel deletion).
#
# Tools tried in order:
#   - sha256sum (Linux, Git Bash on Windows usually has it)
#   - shasum -a 256 (macOS default)
#   - openssl dgst -sha256 (broad fallback)
#   - "no-sha-available" sentinel (graceful degrade — no minimal-shell support)
#
# collab_sha256 <path>
# Echoes the hex SHA-256 of the file content, or "no-sha-available".

collab_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | awk '{print $NF}'
  else
    echo "no-sha-available"
  fi
}
