#!/usr/bin/env bash
# v0.4.2 (G3): pre-commit hook is portable — no external script dependencies.
# The hook is rendered from scripts/hooks/pre-commit.template at install time
# with scripts/lib/receipt.sh inlined. Once installed, it does NOT depend on
# any path under scripts/ in the user's repo (npm-installed scenario).
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- npm-installed scenario: target repo has no scripts/ dir at all ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET" "${TARGET2:-}" "${TARGET3:-}"' EXIT
cd "$TARGET"
# Bootstrap WITHOUT copying scripts/ into the target (mimics npm consumption).
bash "$SKILL_ROOT/scripts/collab-init.sh" --install-hooks >/dev/null 2>&1
# Confirm: target has NO scripts/ dir (this is the npm reality).
[[ ! -d scripts ]] || { echo "test setup error: target unexpectedly has scripts/" >&2; exit 1; }

start_test "G3: hook installed in repo without scripts/ dir"
[[ -x .git/hooks/pre-commit ]] && ok || fail "pre-commit hook not installed"

start_test "G3: hook contains inlined verify_receipt() body"
grep -q "^verify_receipt() {" .git/hooks/pre-commit && ok || fail "verify_receipt definition not inlined"

start_test "G3: hook does not reference any external scripts/ path"
! grep -qE 'bash[[:space:]]+scripts/' .git/hooks/pre-commit && ok || fail "hook still has external script call"

start_test "G3: hook does not contain the placeholder token"
! grep -q "{{INLINE_RECEIPT_LIB}}" .git/hooks/pre-commit && ok || fail "placeholder still present (substitution failed)"

# --- Soft-warn (default): commit proceeds with stderr warning ---
git config user.email "test@example.com"
git config user.name "Test"
# Stage a docs/agents file with NO Receipt.
mkdir -p docs/agents
cat > docs/agents/claude.md <<'EOF'
# Claude Work Log
A free-form change without any Receipt heading.
EOF
git add docs/agents/claude.md

start_test "G3: soft-warn allows commit when no Receipt staged"
out=$(git commit -m "no receipt test" 2>&1)
status=$?
[[ "$status" == "0" ]] && echo "$out" | grep -q "lacks a Task Receipt" && ok || \
  fail "expected commit to proceed with warning; status=$status output=$out"

# --- Strict mode: commit blocked ---
TARGET2=$(make_tmp_repo)
cd "$TARGET2"
bash "$SKILL_ROOT/scripts/collab-init.sh" --install-hooks >/dev/null 2>&1
git config user.email "test@example.com"
git config user.name "Test"
sed -i 's/^strict:.*/strict: true/' .collab/config.yml
mkdir -p docs/agents
cat > docs/agents/claude.md <<'EOF'
# Claude Work Log
Another change without Receipt.
EOF
git add docs/agents/claude.md

start_test "G3: strict mode blocks commit when no Receipt staged"
out=$(git commit -m "should be blocked" 2>&1 || true)
echo "$out" | grep -q "blocking commit" && ok || fail "expected strict-mode block in stderr; got: $out"

# --- Receipt present: commit succeeds in strict mode ---
cat >> docs/agents/claude.md <<'EOF'

### Task Receipt
- some-file.md ............ updated
EOF
git add docs/agents/claude.md

start_test "G3: strict mode allows commit when Receipt is present"
git commit -m "with receipt" >/dev/null 2>&1
status=$?
[[ "$status" == "0" ]] && ok || fail "commit failed despite Receipt being present (status=$status)"

# --- Re-install idempotency under templating ---
TARGET3=$(make_tmp_repo)
cd "$TARGET3"
bash "$SKILL_ROOT/scripts/collab-init.sh" --install-hooks >/dev/null 2>&1
hash1=$(sha256sum .git/hooks/pre-commit | awk '{print $1}')
bash "$SKILL_ROOT/scripts/collab-init.sh" --install-hooks >/dev/null 2>&1
hash2=$(sha256sum .git/hooks/pre-commit | awk '{print $1}')

start_test "G3: re-install produces byte-identical hook"
[[ "$hash1" == "$hash2" ]] && ok || fail "hook differs after re-install (templating not deterministic?)"

cd "$SKILL_ROOT"
report
