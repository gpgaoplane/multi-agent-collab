#!/usr/bin/env bash
# Migrate v0.3.0 -> v0.4.0.
#
# v0.4.0 introduces calling-agent-only fresh installs (Group A of the v0.4.0
# plan). Existing v0.3.0 repos may have all three first-class agents
# auto-installed at fresh-bootstrap time, even when only one was actually used.
# This migration detects agents with seed-only work logs (no real entries, no
# handoff blocks) and offers to prune them.
#
# - Default (interactive tty): prompt per-agent, default NO.
# - Non-interactive ($COLLAB_MIGRATE_NONINTERACTIVE=1, $CI=true, or no tty):
#   keep everything. Conservative; never deletes without explicit user yes.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

echo
echo ">>> Upgrade summary (v0.3.0 → v0.4.0):"
echo ">>>   - BREAKING: collab-init bootstraps only the calling agent."
echo ">>>     Detection: --agent flag > \$COLLAB_AGENT > env probe > hard-fail."
echo ">>>   - AI_AGENTS.md Current Adapters table is now dynamic."
echo ">>>   - Work-log rotation via collab-rotate-log.sh (300-line default)."
echo ">>>   - collab-handoff pickup verb for receivers."
echo ">>>   - User vocabulary expanded: sender + receiver phrases in PROTOCOL.md."
echo ">>>   - Post-compact ritual added to AI_AGENTS.md and AGENTS.md."
echo ">>>   - This migration may prompt to prune unused agents (interactive)."
echo ">>>   - See CHANGELOG.md for full release notes."
echo

is_seed_only() {
  local log="$1"
  [[ -f "$log" ]] || return 0
  grep -qE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$log" && return 1
  grep -q '<!-- collab:handoff:start id=' "$log" && return 1
  return 0
}

remove_agent() {
  local name="$1"
  local desc=".collab/agents.d/${name}.yml"
  [[ -f "$desc" ]] || return 0

  local adapter memory log
  adapter=$(awk -F': *' '/^adapter_path:/ { print $2 }' "$desc")
  memory=$(awk -F': *'  '/^memory_dir:/ { print $2 }' "$desc")
  log=$(awk -F': *'     '/^log_path:/ { print $2 }' "$desc")

  [[ -n "$adapter" && -e "$adapter" ]] && rm -f "$adapter"
  if [[ -n "$memory" && -d "$memory" ]]; then
    rm -rf "$memory"
    # If memory_dir is .<name>/memory, also clean the parent .<name>/.
    local parent="${memory%/*}"
    [[ -n "$parent" && -d "$parent" ]] && rmdir "$parent" 2>/dev/null || true
  fi
  [[ -n "$log" && -f "$log" ]] && rm -f "$log"
  rm -f "$desc"

  # INDEX cleanup: remove rows naming this agent's paths.
  if [[ -f .collab/INDEX.md ]]; then
    awk -v a="$adapter" -v m="$memory" -v l="$log" '
      a != "" && index($0, a) > 0 { next }
      m != "" && index($0, m) > 0 { next }
      l != "" && index($0, l) > 0 { next }
      { print }
    ' .collab/INDEX.md > .collab/INDEX.md.tmp
    mv .collab/INDEX.md.tmp .collab/INDEX.md
  fi

  echo "migration: removed agent $name (adapter, memory, log, descriptor, INDEX rows)"
}

prompt_yes_no() {
  local q="$1"
  local ans
  read -r -p "$q [y/N] " ans </dev/tty || ans=""
  [[ "$ans" =~ ^[Yy]$ ]]
}

interactive=1
if [[ ! -t 0 || -n "${COLLAB_MIGRATE_NONINTERACTIVE:-}" || -n "${CI:-}" ]]; then
  interactive=0
fi

# The calling agent (whoever ran collab-init) is by definition wanted. Never
# prompt to prune them, even if their work log is still seed-only — they may
# just be onboarding into this repo right now.
caller="${COLLAB_AGENT:-}"

unused=()
for desc in .collab/agents.d/*.yml; do
  [[ -f "$desc" ]] || continue
  base=$(basename "$desc" .yml)
  [[ "$base" == _* ]] && continue
  [[ -n "$caller" && "$base" == "$caller" ]] && continue
  log=$(awk -F': *' '/^log_path:/ { print $2 }' "$desc")
  if is_seed_only "$log"; then
    unused+=("$base")
  fi
done

if [[ ${#unused[@]} -eq 0 ]]; then
  echo "migration 0.3.0 -> 0.4.0: all installed agents have activity; nothing to prune."
  exit 0
fi

echo "migration 0.3.0 -> 0.4.0: detected agents with seed-only work logs:"
for name in "${unused[@]}"; do
  echo "  - $name"
done

if [[ $interactive -eq 0 ]]; then
  if [[ -n "${COLLAB_MIGRATE_REMOVE_ALL_SEED:-}" ]]; then
    echo "migration: non-interactive + COLLAB_MIGRATE_REMOVE_ALL_SEED=1 — pruning all flagged agents."
    for name in "${unused[@]}"; do
      remove_agent "$name"
    done
    echo "migration 0.3.0 -> 0.4.0 complete"
    exit 0
  fi
  echo "migration: non-interactive mode (CI / no-tty / COLLAB_MIGRATE_NONINTERACTIVE) — keeping all agents."
  echo "migration 0.3.0 -> 0.4.0 complete"
  exit 0
fi

echo
echo "Pruning removes adapter, memory dir, work log, and descriptor for the agent."
echo "Default answer is NO (keep). Confirm only the ones you actually want gone."
echo

for name in "${unused[@]}"; do
  if prompt_yes_no "Remove unused agent '$name'?"; then
    remove_agent "$name"
  else
    echo "migration: keeping $name"
  fi
done

echo "migration 0.3.0 -> 0.4.0 complete"
