#!/usr/bin/env bash
# Tests for v0.4.1 features:
#   - default_agent in .collab/config.yml as a detection ladder tier
#   - Hard-fail message includes the default_agent hint
#   - --prune-backups [--keep N]
#   - --ack-upgrade auto-prunes old backups
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

# --- default_agent: empty config.yml falls through to env probe ---
TARGET=$(make_tmp_repo)
trap 'rm -rf "$TARGET" "${T2:-}" "${T3:-}" "${T4:-}"' EXIT
cp -R "$SKILL_ROOT/scripts" "$TARGET/scripts"
cp -R "$SKILL_ROOT/templates" "$TARGET/templates"

# Default config.yml ships with `# default_agent: claude` commented out.
(cd "$TARGET" && bash scripts/collab-init.sh --agent claude) >/dev/null 2>&1

start_test "default_agent commented out in shipped config.yml (opt-in)"
grep -qE '^# default_agent:' "$TARGET/.collab/config.yml" && ok || fail "default_agent should be commented opt-in"

# --- default_agent: explicit setting takes effect when env detection would fail ---
T2=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T2/scripts"
cp -R "$SKILL_ROOT/templates" "$T2/templates"

# Set up minimal .collab/config.yml with default_agent before init runs.
mkdir -p "$T2/.collab"
cat > "$T2/.collab/config.yml" <<'EOF'
strict: false
default_agent: codex
EOF

# Run init with NO env hints; default_agent should resolve to codex.
out=$( (cd "$T2" && unset COLLAB_AGENT CLAUDECODE CLAUDE_CODE_SSE_PORT CLAUDE_CODE_OAUTH_TOKEN CODEX_HOME CODEX_CLI GEMINI_CLI GEMINI_API_KEY GOOGLE_AI_API_KEY; bash scripts/collab-init.sh) 2>&1)
rc=$?

start_test "config.yml default_agent resolves to that agent on init"
[[ $rc -eq 0 ]] && [[ -f "$T2/.codex/CODEX.md" ]] && [[ ! -d "$T2/.claude" ]] && ok || fail "expected codex bootstrap: rc=$rc, .codex exists=$([[ -d $T2/.codex ]] && echo yes || echo no), .claude exists=$([[ -d $T2/.claude ]] && echo yes || echo no)"

# --- Precedence: --agent flag > $COLLAB_AGENT > default_agent ---
T3=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T3/scripts"
cp -R "$SKILL_ROOT/templates" "$T3/templates"
mkdir -p "$T3/.collab"
echo "default_agent: gemini" > "$T3/.collab/config.yml"

start_test "--agent flag overrides config.yml default_agent"
(cd "$T3" && bash scripts/collab-init.sh --agent claude) >/dev/null 2>&1
[[ -f "$T3/.claude/CLAUDE.md" ]] && [[ ! -f "$T3/GEMINI.md" ]] && ok || fail "agent flag did not override default_agent"

T4=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T4/scripts"
cp -R "$SKILL_ROOT/templates" "$T4/templates"
mkdir -p "$T4/.collab"
echo "default_agent: gemini" > "$T4/.collab/config.yml"

start_test "\$COLLAB_AGENT overrides config.yml default_agent"
(cd "$T4" && COLLAB_AGENT=claude bash scripts/collab-init.sh) >/dev/null 2>&1
[[ -f "$T4/.claude/CLAUDE.md" ]] && [[ ! -f "$T4/GEMINI.md" ]] && ok || fail "COLLAB_AGENT did not override default_agent"

# --- Hard-fail message includes default_agent hint ---
T5=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T5/scripts"
cp -R "$SKILL_ROOT/templates" "$T5/templates"
out=$( (cd "$T5" && unset COLLAB_AGENT CLAUDECODE CLAUDE_CODE_SSE_PORT CLAUDE_CODE_OAUTH_TOKEN CODEX_HOME CODEX_CLI GEMINI_CLI GEMINI_API_KEY GOOGLE_AI_API_KEY; bash scripts/collab-init.sh) 2>&1)

start_test "hard-fail message mentions default_agent option"
echo "$out" | grep -q "default_agent" && ok || fail "default_agent hint missing from hard-fail"

start_test "hard-fail message documents the full detection ladder"
echo "$out" | grep -q "Detection ladder" && ok || fail "ladder explanation missing"

start_test "hard-fail message warns about Codex/Gemini probe weakness"
echo "$out" | grep -q "best-effort" && ok || fail "probe-weakness caveat missing"

rm -rf "$T5"

# --- --prune-backups: keeps N most recent, deletes the rest ---
T6=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T6/scripts"
cp -R "$SKILL_ROOT/templates" "$T6/templates"
(cd "$T6" && bash scripts/collab-init.sh --agent claude) >/dev/null 2>&1
for i in 1 2 3 4 5 6 7; do
  sleep_marker="0.4.0-to-0.4.1-2026010${i}000000"
  mkdir -p "$T6/.collab/backup/$sleep_marker"
  echo "marker $i" > "$T6/.collab/backup/$sleep_marker/.marker"
  # Stagger mtimes via touch -t so ls -1t orders predictably.
  touch -t "2026010${i}0000" "$T6/.collab/backup/$sleep_marker"
done

start_test "--prune-backups --keep 3 retains exactly 3 backups"
(cd "$T6" && bash scripts/collab-init.sh --prune-backups --keep 3) >/dev/null 2>&1
n=$(ls -1 "$T6/.collab/backup/" | wc -l | tr -d ' ')
assert_eq "3" "$n"

start_test "--prune-backups keeps the most recent (highest mtime) backups"
remaining=$(ls -1 "$T6/.collab/backup/")
echo "$remaining" | grep -q "20260105" && echo "$remaining" | grep -q "20260106" && echo "$remaining" | grep -q "20260107" && ok || fail "kept wrong backups: $remaining"

start_test "--prune-backups --keep 100 (exceeds count) is a no-op"
out=$( (cd "$T6" && bash scripts/collab-init.sh --prune-backups --keep 100) 2>&1)
echo "$out" | grep -q "nothing to prune" && ok || fail "expected nothing-to-prune: $out"

start_test "--prune-backups with no backup dir reports gracefully"
T7=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T7/scripts"
cp -R "$SKILL_ROOT/templates" "$T7/templates"
(cd "$T7" && bash scripts/collab-init.sh --agent claude) >/dev/null 2>&1
out=$( (cd "$T7" && bash scripts/collab-init.sh --prune-backups) 2>&1)
echo "$out" | grep -q "no backup directory" && ok || fail "expected no-backup-dir message: $out"
rm -rf "$T7"

start_test "--prune-backups defaults to keep_recent_backups from config.yml"
# Default config has no keep_recent_backups override; default in script is 5.
T8=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T8/scripts"
cp -R "$SKILL_ROOT/templates" "$T8/templates"
(cd "$T8" && bash scripts/collab-init.sh --agent claude) >/dev/null 2>&1
for i in 1 2 3 4 5 6 7; do
  mkdir -p "$T8/.collab/backup/test-${i}"
  touch -t "2026010${i}0000" "$T8/.collab/backup/test-${i}"
done
# Override default in config to keep_recent_backups: 2
sed -i 's/^keep_recent_backups:.*/keep_recent_backups: 2/' "$T8/.collab/config.yml"
(cd "$T8" && bash scripts/collab-init.sh --prune-backups) >/dev/null 2>&1
n=$(ls -1 "$T8/.collab/backup/" | wc -l | tr -d ' ')
assert_eq "2" "$n"
rm -rf "$T8"

# --- --ack-upgrade auto-prunes old backups ---
T9=$(make_tmp_repo)
cp -R "$SKILL_ROOT/scripts" "$T9/scripts"
cp -R "$SKILL_ROOT/templates" "$T9/templates"
(cd "$T9" && bash scripts/collab-init.sh --agent claude) >/dev/null 2>&1
for i in 1 2 3 4 5 6 7; do
  mkdir -p "$T9/.collab/backup/test-${i}"
  touch -t "2026010${i}0000" "$T9/.collab/backup/test-${i}"
done
# Pretend an upgrade just ran by creating UPGRADE_NOTES.md.
echo "test notes" > "$T9/.collab/UPGRADE_NOTES.md"

start_test "--ack-upgrade auto-prunes backups beyond keep_recent_backups (default 5)"
out=$( (cd "$T9" && bash scripts/collab-init.sh --ack-upgrade) 2>&1)
n=$(ls -1 "$T9/.collab/backup/" | wc -l | tr -d ' ')
assert_eq "5" "$n"

start_test "--ack-upgrade output mentions the prune"
echo "$out" | grep -q "kept 5 most recent" && ok || fail "no prune mention in ack-upgrade output: $out"

rm -rf "$T9"

report
