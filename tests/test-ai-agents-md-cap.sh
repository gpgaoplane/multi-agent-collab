#!/usr/bin/env bash
# Tests for Group G: AI_AGENTS.md line cap + key rule presence.
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
AI_AGENTS="$SKILL_ROOT/templates/AI_AGENTS.md"

LINE_CAP=100

start_test "AI_AGENTS.md line count is at-or-below cap of $LINE_CAP"
lines=$(wc -l < "$AI_AGENTS" | tr -d ' ')
[[ $lines -le $LINE_CAP ]] && ok || fail "AI_AGENTS.md is $lines lines; cap is $LINE_CAP. Trim before adding more rules."

# Each load-bearing rule heading must remain present after the trim.
rules=(
  "Verification"
  "Code modification"
  "Commits"
  "Testing"
  "Security"
  "Multi-agent"
  "Timestamps"
  "Frontmatter"
  "Free file creation"
  "Delta-read"
  "Task Completion Protocol"
  "Post-compact ritual"
)
for rule in "${rules[@]}"; do
  start_test "AI_AGENTS.md retains rule: $rule"
  grep -q "$rule" "$AI_AGENTS" && ok || fail "rule '$rule' missing"
done

# Each section pointer references a real anchor in design.md.
start_test "Frontmatter section points at design.md §6.1"
grep -q 'design.md.* §6.1' "$AI_AGENTS" && ok || fail "design.md §6.1 pointer missing"

start_test "Free file creation section points at design.md §6.6"
grep -q 'design.md.* §6.6' "$AI_AGENTS" && ok || fail "design.md §6.6 pointer missing"

start_test "Delta-read section points at design.md §10"
grep -q 'design.md.* §10' "$AI_AGENTS" && ok || fail "design.md §10 pointer missing"

# The pointers must resolve in design.md (§6.1, §6.6, §10 sections exist).
start_test "design.md has §6.1 Frontmatter"
grep -q '^### 6\.1 Frontmatter' "$SKILL_ROOT/docs/design.md" && ok || fail "design.md §6.1 missing"

start_test "design.md has §6.6 Custom files"
grep -q '^### 6\.6 Custom files' "$SKILL_ROOT/docs/design.md" && ok || fail "design.md §6.6 missing"

start_test "design.md has §10 Delta-read mechanism"
grep -q '^## 10\. Delta-read mechanism' "$SKILL_ROOT/docs/design.md" && ok || fail "design.md §10 missing"

# Critical management blocks must still be present.
start_test "AI_AGENTS.md retains all major marker blocks"
markers=(project-summary current-adapters onboarding behavioral-rules routing-pointer customization-guide agent-log-template)
all_present=1
for m in "${markers[@]}"; do
  grep -q "<!-- collab:${m}:start -->" "$AI_AGENTS" || { fail "marker $m missing"; all_present=0; break; }
done
[[ $all_present -eq 1 ]] && ok

# The cadence rule (D1) must survive after the trim.
start_test "Cadence rule present after trim"
grep -q "Cadence" "$AI_AGENTS" && ok || fail "commit cadence rule lost"

report
