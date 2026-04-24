#!/usr/bin/env bash
# Codex session-start hook (install via Codex config; see README.md).
# Fetches remote + prints commits that the current branch is ahead of origin.
set -euo pipefail
git fetch --all --quiet 2>/dev/null || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
git log --oneline "origin/$branch..HEAD" 2>/dev/null | head -5 || true
