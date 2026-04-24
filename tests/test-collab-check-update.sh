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
echo '{"dist-tags":{"latest":"99.0.0"}}' > /tmp/fake-registry.json
COLLAB_UPDATE_URL="file:///tmp/fake-registry.json" \
  bash "$SKILL_ROOT/scripts/collab-check.sh" 2>&1 | grep -q "newer version" && ok || fail "no advisory emitted"

start_test "CI=true suppresses the advisory"
rm -f .collab/.update-cache
CI=true COLLAB_UPDATE_URL="file:///tmp/fake-registry.json" \
  bash "$SKILL_ROOT/scripts/collab-check.sh" 2>&1 | grep -q "newer version" && fail "advisory should be silent in CI" || ok

start_test "config update_channel: none suppresses advisory"
sed -i 's/update_channel: npm/update_channel: none/' .collab/config.yml
rm -f .collab/.update-cache
COLLAB_UPDATE_URL="file:///tmp/fake-registry.json" \
  bash "$SKILL_ROOT/scripts/collab-check.sh" 2>&1 | grep -q "newer version" && fail "update_channel:none should silence" || ok

cd "$SKILL_ROOT"
rm -rf "$TARGET"
report
