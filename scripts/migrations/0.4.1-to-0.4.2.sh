#!/usr/bin/env bash
# Migrate v0.4.1 -> v0.4.2.
#
# v0.4.2 is a correctness patch: no file renames, no marker schema changes,
# no breaking behavior. The big-ticket fixes are post-ship correctness items
# surfaced by real-world use of v0.4.0/v0.4.1.
#
# Notable user-visible changes:
#   - rotate_keep_recent default lowered 8 -> 3 in shipped templates. EXISTING
#     .collab/config.yml files are NOT rewritten; opt in by editing the value.
#   - .collab/.migrations/ directory is created to record sentinels (the chain
#     runner is now idempotent across re-upgrades).
#   - --ack-upgrade and the upgrade flow now use a richer archive filename
#     schema: UPGRADE_NOTES-<from>-to-<to>-<YYYYMMDDHHMMSS>.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../.." && pwd)"
source "$SKILL_ROOT/scripts/lib/migration-log.sh"

echo
echo ">>> Upgrade summary (v0.4.1 → v0.4.2):"
echo ">>>   - Rotation regex now accepts date-only entry headers"
echo ">>>     (## YYYY-MM-DD ...). Previously required full datetime with T."
echo ">>>     Logs in the wild were silently never rotating."
echo ">>>   - rotate_keep_recent default 8 -> 3 in templates/config.yml."
echo ">>>     EXISTING configs are NOT modified; edit your .collab/config.yml"
echo ">>>     to opt in if you want the new default behavior."
echo ">>>   - bin/cli.js now forwards all flags to bash for init/join/archive/"
echo ">>>     register. Previously these cases silently dropped --agent,"
echo ">>>     --diff, --restore, --prune-backups, --ack-upgrade, etc."
echo ">>>   - Pre-commit hook is self-contained: receipt-verify logic inlined"
echo ">>>     from scripts/lib/receipt.sh at install time. No more dependency"
echo ">>>     on scripts/collab-verify-receipt.sh in npm-installed repos."
echo ">>>   - --restore now prunes migration-created files not in the backup."
echo ">>>     --diff (apply-then-restore) leaves repo byte-equivalent."
echo ">>>   - .collab/VERSION format is validated; garbage content fails fast"
echo ">>>     with guidance. --restore latest still works on a corrupted VERSION."
echo ">>>   - Doubled marker blocks emit a loud merge: WARNING. Refresh paths"
echo ">>>     tolerate the warning so init still completes (visible, not blocking)."
echo ">>>   - Migrations are now idempotent. Sentinels at .collab/.migrations/"
echo ">>>     record successful application; re-running an already-applied"
echo ">>>     migration is a no-op. Legacy migrations are auto-back-filled."
echo ">>>   - UPGRADE_NOTES.md is auto-archived if a prior unacked transient"
echo ">>>     exists. Archive schema: UPGRADE_NOTES-<from>-to-<to>-<HMS>.md."
echo ">>>   - inject_agents_md_section no-ops on orphan markers (defensive)."
echo ">>>   - See CHANGELOG.md for full release notes."
echo

mlog_action "v0.4.1 -> v0.4.2: correctness patch; sentinels added; default rotate_keep_recent lowered."

echo "migration 0.4.1 -> 0.4.2 complete"
