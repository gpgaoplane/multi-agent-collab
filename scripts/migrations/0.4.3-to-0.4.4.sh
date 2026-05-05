#!/usr/bin/env bash
# Migrate v0.4.3 -> v0.4.4.
#
# v0.4.4 is a small correctness patch:
#   - G1: collab-rotate-log.sh appends to existing same-day archive instead of
#     clobbering. Fixes silent data loss on rotate -> change rotate_keep_recent
#     -> rotate-again sequences. No CLI flag added; no opt-in clobber.
#   - G2: collab-check.sh rotation advisory is content-aware. When the live
#     log is over rotate_at_lines but already at rotate_keep_recent (rotation
#     would be a no-op), advisory text suggests config tuning instead of
#     looping the user through advisory -> rotate -> no-op -> advisory.
#   - G3: collab-check.sh --stats entry-count regex aligned with rotate-log.
#     Date-only entry headers (## YYYY-MM-DD title) are now counted in --stats.
#     Projects using date-only headers will see higher counts than under v0.4.3.
#
# v0.4.4 is otherwise additive: no schema changes, no breaking behavior,
# no new flags or subcommands.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../.." && pwd)"
source "$SKILL_ROOT/scripts/lib/migration-log.sh"

echo
echo ">>> Upgrade summary (v0.4.3 -> v0.4.4):"
echo ">>>   - G1: collab-rotate-log.sh same-day re-rotation now APPENDS to the"
echo ">>>     existing archive instead of clobbering. Pre-fix, a second rotation"
echo ">>>     on the same calendar day silently destroyed the prior archive's"
echo ">>>     entry bodies. New behavior: H3 '### Continued — rotated <ISO>'"
echo ">>>     separator + appended block. No CLI flag added."
echo ">>>   - G2: collab-check.sh rotation advisory is content-aware. When"
echo ">>>     entry_count <= rotate_keep_recent (rotation would be a no-op),"
echo ">>>     advisory now points at rotate_at_lines tuning instead of looping"
echo ">>>     the user through useless rotate invocations."
echo ">>>   - G3: collab-check.sh --stats regex aligned with rotate-log. Projects"
echo ">>>     using date-only entry headers will see correct (higher) entry"
echo ">>>     counts in --stats output. May differ from prior v0.4.3 output."
echo ">>>   - Note: rotations are user-initiated; do not invoke concurrently."
echo ">>>     Two parallel appends would interleave bytes (worse than two"
echo ">>>     parallel clobbers, which produced one valid archive). Concurrent"
echo ">>>     rotation locking is out of scope for v0.4.4."
echo ">>>   - No state changes required. Re-init refreshes managed sections."
echo ">>>   - See CHANGELOG.md for full release notes."
echo

mlog_action "v0.4.3 -> v0.4.4: archive append + advisory + --stats regex; no state changes."

echo "migration 0.4.3 -> 0.4.4 complete"
