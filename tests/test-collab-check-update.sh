#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TARGET=$(make_tmp_repo)
cd "$TARGET"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1

start_test "collab-check with local-file update channel prints advisory when version newer"
# Write a fake registry file and point COLLAB_UPDATE_URL at it.
# Explicitly clear CI — GitHub Actions (and other CI envs) set CI=true, which
# would short-circuit check_for_update and hide the advisory we want to see.
# Output is captured before grepping: piping straight into `grep -q` under
# pipefail fails at random when grep exits early and collab-check gets SIGPIPE.
echo '{"dist-tags":{"latest":"99.0.0"}}' > "$TARGET/fake-registry.json"
out=$(env -u CI COLLAB_UPDATE_URL="file://$TARGET/fake-registry.json" \
  bash "$SKILL_ROOT/scripts/collab-check.sh" 2>&1)
grep -q "newer version" <<<"$out" && ok || fail "no advisory emitted"

start_test "CI=true suppresses the advisory"
rm -f .collab/.update-cache
out=$(CI=true COLLAB_UPDATE_URL="file://$TARGET/fake-registry.json" \
  bash "$SKILL_ROOT/scripts/collab-check.sh" 2>&1)
grep -q "newer version" <<<"$out" && fail "advisory should be silent in CI" || ok

start_test "config update_channel: none suppresses advisory"
sed_inplace 's/update_channel: npm/update_channel: none/' .collab/config.yml
rm -f .collab/.update-cache
out=$(env -u CI COLLAB_UPDATE_URL="file://$TARGET/fake-registry.json" \
  bash "$SKILL_ROOT/scripts/collab-check.sh" 2>&1)
grep -q "newer version" <<<"$out" && fail "update_channel:none should silence" || ok

cd "$SKILL_ROOT"
rm -rf "$TARGET"
report
