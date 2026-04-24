#!/usr/bin/env bash
# Migrate a v0.2.0 install to v0.3.0.
# Non-destructive: copies new files, leaves user content alone.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATES="$SKILL_ROOT/templates"

# config.yml
if [[ ! -f .collab/config.yml ]]; then
  cp "$TEMPLATES/config.yml" .collab/config.yml
  echo "migration: installed .collab/config.yml"
fi

# Hooks are opt-in via --install-hooks; migration does not auto-install them.
# Empty-state seeds are refreshed by re-init's refresh_managed_sections path.

echo "migration 0.2.0 -> 0.3.0 complete"
