#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
VERIFY="$SKILL_ROOT/scripts/collab-verify-receipt.sh"

TARGET=$(make_tmp_repo)
cd "$TARGET"
bash "$SKILL_ROOT/scripts/collab-init.sh" >/dev/null 2>&1
git add -A && git commit -q -m "bootstrap" 2>/dev/null

LOG=docs/agents/claude.md

# --- Standalone mode (no git): file-presence fallback ---
start_test "standalone: verify passes when file contains a receipt"
tmp=$(mktemp); cp "$LOG" "$tmp"
printf '\n### Task Receipt\nUpdates: none\n' >> "$tmp"
(cd /tmp && bash "$VERIFY" "$tmp") && ok || fail "standalone with receipt should pass"
rm -f "$tmp"

start_test "standalone: verify fails when file lacks a receipt"
tmp=$(mktemp); echo "# log without receipt" > "$tmp"
(cd /tmp && bash "$VERIFY" "$tmp") && fail "standalone without receipt should fail" || ok
rm -f "$tmp"

# --- Diff-based mode (inside a git work tree with HEAD) ---
start_test "diff mode: staged change that adds a receipt passes"
cat >> "$LOG" <<'EOF'

## 2026-04-23 session
Did the thing.

### Task Receipt
Updates:
- README.md ... smoke test
EOF
git add "$LOG"
bash "$VERIFY" "$LOG" && ok || fail "adding receipt should pass"
git commit -q -m "commit with receipt"

start_test "diff mode: stale receipt (no new one in staged diff) FAILS"
# Make any non-receipt change and stage it. The existing receipt from the
# previous commit must NOT satisfy the check — this is the B6 regression guard.
echo "small tweak" >> "$LOG"
git add "$LOG"
bash "$VERIFY" "$LOG" && fail "stale receipt should fail" || ok
git checkout -q "$LOG"

start_test "diff mode: short-form receipt passes"
cat >> "$LOG" <<'EOF'

### Task Receipt
Updates: none applicable (docs-only tweak)
EOF
git add "$LOG"
bash "$VERIFY" "$LOG" && ok || fail "short form should pass"
git commit -q -m "short form"

start_test "diff mode: a line that REMOVES a receipt must NOT count as adding"
# Stage a delete-only diff (remove the last receipt). This must fail; grep
# for '^+### Task Receipt' — not just '### Task Receipt' — is what prevents this.
sed -i '/^### Task Receipt$/,$d' "$LOG"
git add "$LOG"
bash "$VERIFY" "$LOG" && fail "deletion diff should not count as adding a receipt" || ok
git checkout -q "$LOG"

cd "$SKILL_ROOT"
rm -rf "$TARGET"
report
