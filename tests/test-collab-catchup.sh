#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
CATCHUP="$SKILL_ROOT/scripts/collab-catchup.sh"

TARGET=$(make_tmp_repo)
cd "$TARGET"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1

# Simulate: claude state.md watermark is "2020-01-01T00:00:00-00:00",
# INDEX has entries newer than that.
STATE=.claude/memory/state.md

start_test "catchup prints files newer than watermark"
sed -i 's|Last read INDEX at: (not yet read)|Last read INDEX at: 2020-01-01T00:00:00-00:00|' "$STATE"
output=$(bash "$CATCHUP" --agent claude 2>&1)
echo "$output" | grep -q ".collab/ROUTING.md" && ok || fail "expected ROUTING.md in catchup output"

start_test "catchup does NOT mutate watermark (dry by default)"
wm=$(grep "Last read INDEX at:" "$STATE")
echo "$wm" | grep -q "2020-01-01" && ok || fail "watermark mutated: $wm"

start_test "idx_list_with_timestamps returns last-updated column (not status)"
# Off-by-one regression guard: write a fixture INDEX with distinct values in
# every column, assert we read the last-updated column specifically.
cat > .collab/INDEX.md <<'EOF'
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
---
# File Registry

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
| fixture/x.md | doc | tester | STATUS_MARKER | LASTUPDATED_MARKER |
<!-- collab:index:end -->
EOF
output=$( (source "$SKILL_ROOT/scripts/lib/index.sh"; idx_list_with_timestamps ".collab/INDEX.md") )
echo "$output" | grep -q "LASTUPDATED_MARKER" && ok || fail "returned wrong column: $output"
echo "$output" | grep -q "STATUS_MARKER" && fail "read status column by mistake" || ok

# Restore INDEX for remaining tests (remove first — re-init preserves existing files).
rm -f .collab/INDEX.md
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1

start_test "catchup with up-to-date watermark prints nothing"
NOW=$(bash "$SKILL_ROOT/scripts/collab-now.sh")
sed -i "s|Last read INDEX at: .*|Last read INDEX at: $NOW|" "$STATE"
output=$(bash "$CATCHUP" --agent claude 2>&1)
[[ -z "$output" || "$output" =~ "up to date" ]] && ok || fail "expected empty/up-to-date, got: $output"

cd "$SKILL_ROOT"
rm -rf "$TARGET"

# --- ack error path: missing watermark section ---
TARGET3=$(make_tmp_repo)
cd "$TARGET3"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1
STATE3=.claude/memory/state.md

start_test "ack errors non-zero when the watermark line is absent from state.md"
# Remove the watermark line
awk '!/Last read INDEX at:/' "$STATE3" > /tmp/state-no-wm
mv /tmp/state-no-wm "$STATE3"
set +e
bash "$CATCHUP" ack --agent claude >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" != "0" ]] && ok || fail "ack on missing watermark returned success exit code"

cd "$SKILL_ROOT"
rm -rf "$TARGET3"

# --- Two-phase round-trip (Task 3) ---
TARGET4=$(make_tmp_repo)
cd "$TARGET4"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1
STATE4=.claude/memory/state.md

# Roll the watermark back so preview has something to show.
sed -i 's|Last read INDEX at: (not yet read)|Last read INDEX at: 2020-01-01T00:00:00-00:00|' "$STATE4"

start_test "ack updates watermark to a current ISO timestamp"
bash "$CATCHUP" ack --agent claude >/dev/null 2>&1
new_wm=$(grep "Last read INDEX at:" "$STATE4")
echo "$new_wm" | grep -qE "Last read INDEX at: 20[0-9]{2}-[0-9]{2}-[0-9]{2}T" && ok || fail "watermark not advanced: $new_wm"

start_test "after ack, subsequent preview reports 'up to date'"
output=$(bash "$CATCHUP" preview --agent claude 2>&1)
echo "$output" | grep -q "up to date" && ok || fail "expected up-to-date after ack, got: $output"

start_test "ack prints the new watermark value on stdout"
out=$(bash "$CATCHUP" ack --agent claude 2>&1)
echo "$out" | grep -qE "^watermark updated: 20[0-9]{2}-[0-9]{2}-[0-9]{2}T" && ok || fail "ack did not echo new watermark: $out"

cd "$SKILL_ROOT"
rm -rf "$TARGET4"

report
