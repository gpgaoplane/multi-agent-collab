#!/usr/bin/env bash
# Migrate v0.4.2 -> v0.4.3.
#
# v0.4.3 adds the `update` subcommand — a single-trigger orchestration wrapper
# around the existing init upgrade flow with pre-flight version check,
# interactive confirmation prompt, and post-flight ack reminder. Vocabulary
# in PROTOCOL.md is tightened to reference the new command 1:1.
#
# Genuinely new state-management behavior: `update --rollback` cleans up
# .collab/.migrations/ sentinels for rolled-back migrations. Without this,
# the next `update` after a rollback would silently skip migrations because
# sentinels say "applied" while .collab/VERSION reverted.
#
# v0.4.3 is otherwise additive: no file renames, no marker schema changes,
# no breaking behavior changes. The v0.4.2 multi-step upgrade flow
# (init -> read notes -> --ack-upgrade) continues to work — `update` just
# wraps it into one command.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../.." && pwd)"
source "$SKILL_ROOT/scripts/lib/migration-log.sh"

echo
echo ">>> Upgrade summary (v0.4.2 → v0.4.3):"
echo ">>>   - New 'update' subcommand: 'npx @gpgaoplane/multi-agent-collab update'"
echo ">>>     Wraps the init upgrade flow with pre-flight version check,"
echo ">>>     interactive confirmation prompt, and post-flight ack reminder."
echo ">>>     Mode flags: --check, --ack, --rollback. Modifier flags: --yes,"
echo ">>>     --diff-first, --no-backup, --force-dirty."
echo ">>>   - 'update --rollback' cleans up stale migration sentinels in"
echo ">>>     .collab/.migrations/ for migrations being rolled back. This"
echo ">>>     fixes a latent bug where a post-rollback re-upgrade would"
echo ">>>     silently skip migration bodies because sentinels lingered."
echo ">>>   - PROTOCOL.md vocabulary section now references the 'update'"
echo ">>>     command directly. 'update the framework' triggers the wrapper."
echo ">>>     NOTE: existing installs' .collab/PROTOCOL.md is NOT auto-refreshed"
echo ">>>     (re_init_shared treats PROTOCOL.md as create-once). The OLD"
echo ">>>     vocabulary (3-command flow: init -> read notes -> --ack-upgrade)"
echo ">>>     remains functionally equivalent; users who want the new vocab"
echo ">>>     can manually copy templates/collab/PROTOCOL.md over their copy."
echo ">>>   - version_le and migration sentinel helpers extracted from"
echo ">>>     collab-init.sh into scripts/lib/semver.sh and scripts/lib/migrations.sh."
echo ">>>     Pure refactor; no behavior change."
echo ">>>   - No state changes required. Re-init refreshes managed sections."
echo ">>>   - See CHANGELOG.md for full release notes."
echo

mlog_action "v0.4.2 -> v0.4.3: 'update' subcommand wrapper; helpers extracted to lib; no state changes."

echo "migration 0.4.2 -> 0.4.3 complete"
