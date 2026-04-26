#!/usr/bin/env bash
# Migrate a v0.2.0 install to v0.3.0.
# Non-destructive: copies new files, leaves user content alone.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATES="$SKILL_ROOT/templates"

echo
echo ">>> Upgrade summary (v0.2.0 → v0.3.0):"
echo ">>>   - Adds .collab/config.yml (strict + update_channel keys)."
echo ">>>   - Cross-agent handoff: collab-handoff with chain support."
echo ">>>   - Two-phase catchup (preview + ack) for delta-read."
echo ">>>   - Optional pre-commit Receipt verifier (--install-hooks)."
echo ">>>   - Update advisory in collab-check (24h cached)."
echo ">>>   - See CHANGELOG.md for full release notes."
echo

# config.yml
if [[ ! -f .collab/config.yml ]]; then
  cp "$TEMPLATES/config.yml" .collab/config.yml
  echo "migration: installed .collab/config.yml"
fi

# Hooks are opt-in via --install-hooks; migration does not auto-install them.
# Empty-state seeds are refreshed by re-init's refresh_managed_sections path.

echo "migration 0.2.0 -> 0.3.0 complete"
