#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- Fresh repo, no prior hook ---
TARGET=$(make_tmp_repo)
cd "$TARGET"

start_test "--install-hooks creates managed hook with sentinel"
bash "$SKILL_ROOT/scripts/collab-init.sh" --install-hooks >/dev/null 2>&1
[[ -x .git/hooks/pre-commit ]] && ok || fail "pre-commit hook not installed or not executable"

start_test "managed hook has the collab:managed-hook sentinel"
grep -q "^# collab:managed-hook" .git/hooks/pre-commit && ok || fail "sentinel missing"

start_test "managed hook invokes verify_receipt (inlined function, no external script)"
grep -q "verify_receipt " .git/hooks/pre-commit && ok || fail "verify_receipt call missing"

start_test "v0.4.2: managed hook has inlined verify_receipt() body (no external dep)"
grep -q "^verify_receipt() {" .git/hooks/pre-commit && ok || fail "inlined verify_receipt definition missing"

start_test "v0.4.2: managed hook does NOT reference scripts/collab-verify-receipt.sh"
! grep -q "bash scripts/collab-verify-receipt" .git/hooks/pre-commit && ok || fail "hook still references external script"

start_test "v0.4.2: managed-hook sentinel still on line 2 after templating"
sentinel_line=$(grep -n "^# collab:managed-hook" .git/hooks/pre-commit | head -1 | cut -d: -f1)
[[ "$sentinel_line" == "2" ]] && ok || fail "sentinel on line $sentinel_line (expected 2)"

start_test "collab config.yml is created with strict: false default"
[[ -f .collab/config.yml ]] && grep -qE '^strict:\s*false' .collab/config.yml && ok || fail "config.yml missing or wrong default"

cd "$SKILL_ROOT"
rm -rf "$TARGET"

# --- Fresh repo with an existing user hook BEFORE install ---
TARGET=$(make_tmp_repo)
cd "$TARGET"
mkdir -p .git/hooks
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# USER_HOOK_MARKER — this is the user's own pre-commit logic
echo "user hook ran"
EOF
chmod +x .git/hooks/pre-commit

bash "$SKILL_ROOT/scripts/collab-init.sh" --install-hooks >/dev/null 2>&1

start_test "user's pre-existing hook is preserved as pre-commit.local"
grep -q "USER_HOOK_MARKER" .git/hooks/pre-commit.local && ok || fail "user hook lost"

start_test "managed hook now occupies pre-commit and has sentinel"
grep -q "^# collab:managed-hook" .git/hooks/pre-commit && ok || fail "managed sentinel missing"

start_test "managed hook has a delegation block"
grep -q "^# collab:delegation" .git/hooks/pre-commit && ok || fail "delegation marker missing"

# --- Re-run idempotency ---
bash "$SKILL_ROOT/scripts/collab-init.sh" --install-hooks >/dev/null 2>&1

start_test "re-run does NOT clobber pre-commit.local"
grep -q "USER_HOOK_MARKER" .git/hooks/pre-commit.local && ok || fail ".local got clobbered"

start_test "re-run has exactly ONE delegation block"
delegations=$(grep -c "^# collab:delegation" .git/hooks/pre-commit)
[[ "$delegations" == "1" ]] && ok || fail "delegation block count = $delegations (expected 1)"

cd "$SKILL_ROOT"
rm -rf "$TARGET"
report
