#!/usr/bin/env bash
# Migrate v0.4.0 -> v0.4.1.
#
# v0.4.1 is additive: no file renames, no marker schema changes, no breaking
# behavior. The new `default_agent` config key is optional (absence falls
# through to the existing detection probe). The new `--prune-backups` and
# auto-prune-on-ack are pure feature additions. Hard-fail message change is
# string-only.
#
# This migration just emits the upgrade summary so users know what changed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../.." && pwd)"
source "$SKILL_ROOT/scripts/lib/migration-log.sh"

echo
echo ">>> Upgrade summary (v0.4.0 → v0.4.1):"
echo ">>>   - New optional .collab/config.yml key: default_agent"
echo ">>>     Set this to make detection persistent per-repo without env vars."
echo ">>>     Detection ladder is now: --agent flag > \$COLLAB_AGENT >"
echo ">>>     config.yml default_agent > env probe > hard-fail."
echo ">>>   - New collab-init --prune-backups [--keep N] flag for cleaning"
echo ">>>     up old .collab/backup/ directories (default: keep 5)."
echo ">>>   - --ack-upgrade auto-prunes backups beyond keep_recent_backups"
echo ">>>     (also default 5; configurable in .collab/config.yml)."
echo ">>>   - Hard-fail message expanded to mention default_agent option."
echo ">>>   - No state changes required. Re-init refreshes managed sections."
echo ">>>   - See CHANGELOG.md for full release notes."
echo

mlog_action "v0.4.0 -> v0.4.1: additive release; no state changes."

echo "migration 0.4.0 -> 0.4.1 complete"
