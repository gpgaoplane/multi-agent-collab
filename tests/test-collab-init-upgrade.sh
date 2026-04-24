#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP"' EXIT

cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

# Fake a v0.1.0 bootstrapped state: run current bootstrap, then ROLLBACK
# the version marker to 0.1.0 so detect_mode → upgrade.
(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1
echo "0.1.0" > "$TMP/.collab/VERSION"

# Simulate v0.1.0 state: that version didn't produce an AGENTS.md.
rm -f "$TMP/AGENTS.md"

# Run v0.2.0 upgrade.
(cd "$TMP" && bash scripts/collab-init.sh) >/dev/null 2>&1

start_test "upgrade bumps .collab/VERSION to shipped version"
v=$(cat "$TMP/.collab/VERSION" | tr -d '[:space:]')
shipped=$(cat "$SKILL_ROOT/templates/collab/VERSION" | tr -d '[:space:]')
assert_eq "$shipped" "$v"

start_test "upgrade creates AGENTS.md"
assert_file_exists "$TMP/AGENTS.md"

start_test "upgraded AGENTS.md has managed markers"
assert_file_contains "$TMP/AGENTS.md" "<!-- collab:agents-md:start -->"

start_test "upgraded repo still passes collab-check"
(cd "$TMP" && bash scripts/collab-check.sh) >/dev/null 2>&1 && ok || fail "check failed post-upgrade"

# Now test --join flow on upgraded repo.
(cd "$TMP" && bash scripts/collab-init.sh --join cline) >/dev/null 2>&1

start_test "post-upgrade --join unknown agent creates adapter"
assert_file_exists "$TMP/.cline/CLINE.md"

start_test "post-upgrade --join adds row to INDEX"
assert_file_contains "$TMP/.collab/INDEX.md" ".cline/CLINE.md"

report
