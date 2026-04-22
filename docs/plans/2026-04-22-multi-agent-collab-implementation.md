---
status: active
type: implementation-plan
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are executing the build of multi-agent-collab v0.1.0"
skip-if: "you are consuming the skill, not building it"
related: [docs/design.md]
---

# Multi-Agent Collab — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the `multi-agent-collab` skill end-to-end — templates, scripts, descriptors, and reference docs — so that running `./scripts/collab-init.sh` in any repo produces the canonical multi-agent collaboration structure defined in `docs/design.md`.

**Architecture:** Pure-bash scripts with a small Python fallback for portability. Templates are inert markdown/YAML files. The bootstrap script (`collab-init.sh`) composes templates + descriptors into a target repo using marker-guided merge for idempotent re-runs. No external dependencies beyond `bash`, `git`, and (optionally) `python3`.

**Tech Stack:** Bash 4+, POSIX `awk`, Python 3 (fallback for YAML parsing edge cases), Bats-style bash test harness (inherited pattern from `graceful-wrap-up/tests/`).

---

## Roadmap

24 tasks in 8 groups. Phase A only (skill build). Phase B (graceful-wrap-up migration) is a separate plan.

| Group | Tasks | What it delivers |
|---|---|---|
| 1. Scaffolding | 1–2 | Repo skeleton, test harness, licensing |
| 2. Core utilities (TDD) | 3–6 | Timestamp, frontmatter lib, INDEX lib, marker merge |
| 3. User-facing scripts (TDD) | 7–9 | `collab-register`, `collab-archive`, `collab-check` |
| 4. Templates | 10–14 | AI_AGENTS, `.collab/` docs, adapters, descriptors, memory |
| 5. Bootstrap command | 15–18 | `collab-init.sh` — fresh, re-init, legacy, flags |
| 6. Integration tests | 19–21 | E2E bootstrap, re-init idempotency, add-agent |
| 7. Optional hardening | 22 | Claude-specific pre-commit hook for Receipts |
| 8. Ship | 23–24 | README/CONTRIBUTING, tag v0.1.0 |

## Prerequisites

- Working directory: `D:\Projects\self-skills\multi-agent-collab\` (already cloned, already has initial commit with design doc + README).
- Tools verified present: `bash --version`, `git --version`, `python3 --version` (or `python`, or `py`).
- Remote: `origin` points at `https://github.com/gpgaoplane/multi-agent-collab.git`.

## Conventions

- **TDD for scripts.** Write failing test → verify fail → implement → verify pass → commit. No exceptions for scripts.
- **No TDD for templates.** Templates are inert content. Write the file, use integration tests (Tasks 19–21) to cover behavior.
- **Commit style:** imperative mood, one logical change per commit, named files staged (`git add <file>...`, never `git add -A`).
- **Bash mode:** `set -euo pipefail` in every script.
- **Paths in plan:** all paths relative to `D:\Projects\self-skills\multi-agent-collab\` unless noted.
- **Test harness:** simple PASS/FAIL counter, run all tests via `./tests/run-all.sh`.

---

## Task 1: Repo scaffolding and licensing

**Files:**
- Create: `.gitignore`
- Create: `LICENSE` (MIT, standard template)
- Create: `CONTRIBUTING.md`
- Create: `templates/.gitkeep` (empty placeholder)
- Create: `scripts/.gitkeep`
- Create: `scripts/lib/.gitkeep`
- Create: `tests/.gitkeep`

**Step 1: Create `.gitignore`**

```gitignore
# Test artifacts
/tests/tmp/
/tests/*.log

# Local editor scratch
.vscode/
.idea/
*.swp
*.bak

# OS
.DS_Store
Thumbs.db
```

**Step 2: Create `LICENSE` (MIT)**

Use the standard MIT template with `Copyright (c) 2026 gpgaoplane` in the header.

**Step 3: Create `CONTRIBUTING.md`**

```markdown
# Contributing to multi-agent-collab

## Scope

This skill is intentionally small. Before opening a PR, read `docs/design.md` — especially §19 "What we deliberately don't build." If your change adds enforcement, locking, or cross-repo sync, it likely belongs elsewhere.

## Running tests

```bash
./tests/run-all.sh
```

All tests must pass before merge. TDD is required for new scripts.

## Commit style

- Imperative mood: "add X", not "added X"
- One logical change per commit
- Reference the task in `docs/plans/*.md` when applicable

## Reporting issues

Open a GitHub issue. For behavior mismatches vs `docs/design.md`, quote the section.
```

**Step 4: Create placeholders**

```bash
touch templates/.gitkeep scripts/.gitkeep scripts/lib/.gitkeep tests/.gitkeep
```

**Step 5: Commit**

```bash
git add .gitignore LICENSE CONTRIBUTING.md templates/.gitkeep scripts/.gitkeep scripts/lib/.gitkeep tests/.gitkeep
git commit -m "chore: scaffold repo structure and licensing"
```

---

## Task 2: Test harness

**Files:**
- Create: `tests/harness.sh` (shared functions, sourced by each test)
- Create: `tests/run-all.sh` (runs every `test-*.sh` in `tests/`)
- Create: `tests/test-harness.sh` (smoke test for the harness itself)

**Step 1: Write `tests/harness.sh`**

```bash
#!/usr/bin/env bash
# Shared test utilities for multi-agent-collab.
# Sourced by every tests/test-*.sh file.

set -uo pipefail

PASS=0
FAIL=0
CURRENT_TEST=""

ok() {
  ((++PASS))
  return 0
}

fail() {
  ((++FAIL))
  echo "  FAIL: ${CURRENT_TEST:-unnamed} — $1" >&2
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-values differ}"
  if [[ "$expected" == "$actual" ]]; then
    ok
  else
    fail "$msg: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="${3:-substring missing}"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok
  else
    fail "$msg: '$needle' not found in output"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "$path" ]] && ok || fail "file missing: $path"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if [[ -f "$path" ]] && grep -qF "$needle" "$path"; then
    ok
  else
    fail "file $path missing substring: $needle"
  fi
}

start_test() {
  CURRENT_TEST="$1"
}

report() {
  echo
  echo "Tests: PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
}

make_tmp_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  echo "$dir"
}
```

**Step 2: Write `tests/run-all.sh`**

```bash
#!/usr/bin/env bash
# Runs every tests/test-*.sh file in sequence.
set -uo pipefail

cd "$(dirname "$0")"
total_pass=0
total_fail=0
any_file_failed=0

for f in test-*.sh; do
  [[ -f "$f" ]] || continue
  echo "=== $f ==="
  if bash "$f"; then
    :
  else
    any_file_failed=1
  fi
done

echo
if [[ $any_file_failed -eq 0 ]]; then
  echo "ALL TEST FILES PASSED"
  exit 0
else
  echo "ONE OR MORE TEST FILES FAILED"
  exit 1
fi
```

**Step 3: Write `tests/test-harness.sh` (smoke test)**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

start_test "assert_eq basic"
assert_eq "foo" "foo"

start_test "assert_contains basic"
assert_contains "world" "hello world"

start_test "assert_file_exists on this file"
assert_file_exists "$(dirname "$0")/harness.sh"

report
```

**Step 4: Run harness smoke test**

```bash
chmod +x tests/*.sh
bash tests/test-harness.sh
```

Expected output: `Tests: PASS=3 FAIL=0`

**Step 5: Commit**

```bash
git add tests/harness.sh tests/run-all.sh tests/test-harness.sh
git commit -m "test: add bash test harness with PASS/FAIL counter and tmp repo helper"
```

---

## Task 3: Timestamp helper — `scripts/collab-now.sh`

**Files:**
- Create: `scripts/collab-now.sh`
- Create: `tests/test-collab-now.sh`

**Step 1: Write the failing test — `tests/test-collab-now.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
NOW="$HERE/../scripts/collab-now.sh"

start_test "collab-now emits ISO 8601 with timezone offset"
out=$(bash "$NOW")
# Expect: YYYY-MM-DDTHH:MM:SS±HH:MM
if [[ "$out" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$ ]]; then
  ok
else
  fail "unexpected format: $out"
fi

start_test "collab-now outputs exactly one line"
lines=$(bash "$NOW" | wc -l)
assert_eq "1" "$(echo "$lines" | tr -d ' ')"

report
```

**Step 2: Run test to verify it fails**

```bash
bash tests/test-collab-now.sh
```

Expected: both tests FAIL because `scripts/collab-now.sh` doesn't exist yet.

**Step 3: Write minimal implementation — `scripts/collab-now.sh`**

```bash
#!/usr/bin/env bash
# Prints current timestamp in ISO 8601 with timezone offset.
# Example: 2026-04-22T10:15:30-05:00
set -euo pipefail

# GNU date (Linux) supports %:z. BSD date (macOS) needs %z with manual insertion of colon.
# Windows Git Bash ships GNU date. Try %:z first; fall back to %z with sed.
if out=$(date +'%Y-%m-%dT%H:%M:%S%:z' 2>/dev/null) && [[ "$out" == *:* ]]; then
  # Guard: the timezone part (last 6 chars) must contain a colon to count as %:z success.
  tz="${out: -6}"
  if [[ "$tz" == *:* ]]; then
    echo "$out"
    exit 0
  fi
fi

# Fallback: insert colon into ±HHMM → ±HH:MM
out=$(date +'%Y-%m-%dT%H:%M:%S%z')
echo "${out:0: -2}:${out: -2}"
```

**Step 4: Run test to verify it passes**

```bash
chmod +x scripts/collab-now.sh
bash tests/test-collab-now.sh
```

Expected: `Tests: PASS=2 FAIL=0`

**Step 5: Commit**

```bash
git add scripts/collab-now.sh tests/test-collab-now.sh
git commit -m "feat: add collab-now.sh timestamp helper with ISO 8601 output"
```

---

## Task 4: Frontmatter library — `scripts/lib/frontmatter.sh`

**Files:**
- Create: `scripts/lib/frontmatter.sh`
- Create: `tests/test-frontmatter.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/lib/frontmatter.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/a.md" <<'EOF'
---
status: active
type: work-log
owner: claude
last-updated: 2026-04-22T10:15:30-05:00
---

# Body content
Some body text.
EOF

start_test "fm_get_field reads status"
assert_eq "active" "$(fm_get_field "$TMP/a.md" status)"

start_test "fm_get_field reads multi-word timestamp"
assert_eq "2026-04-22T10:15:30-05:00" "$(fm_get_field "$TMP/a.md" last-updated)"

start_test "fm_get_field missing field returns empty"
assert_eq "" "$(fm_get_field "$TMP/a.md" nonexistent)"

start_test "fm_has_frontmatter detects frontmatter"
fm_has_frontmatter "$TMP/a.md" && ok || fail "frontmatter not detected"

cat > "$TMP/b.md" <<'EOF'
No frontmatter here.
EOF

start_test "fm_has_frontmatter rejects file without frontmatter"
if ! fm_has_frontmatter "$TMP/b.md"; then ok; else fail "false positive"; fi

start_test "fm_set_field updates existing field"
fm_set_field "$TMP/a.md" status stale
assert_eq "stale" "$(fm_get_field "$TMP/a.md" status)"

start_test "fm_set_field preserves body"
assert_file_contains "$TMP/a.md" "Some body text."

start_test "fm_set_field adds missing field"
fm_set_field "$TMP/a.md" new-field "hello"
assert_eq "hello" "$(fm_get_field "$TMP/a.md" new-field)"

report
```

**Step 2: Run test to verify it fails**

```bash
bash tests/test-frontmatter.sh
```

Expected: FAIL — `scripts/lib/frontmatter.sh` doesn't exist.

**Step 3: Write implementation — `scripts/lib/frontmatter.sh`**

```bash
#!/usr/bin/env bash
# YAML frontmatter helpers. Assumes simple key: value pairs, no nested structures.
# Lists are not required for the skill's managed fields (status, type, owner,
# last-updated, read-if, skip-if). `related: []` is written verbatim.

# fm_has_frontmatter <file>
# Returns 0 if the file starts with a YAML frontmatter block (--- on line 1).
fm_has_frontmatter() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  [[ "$(head -n 1 "$file")" == "---" ]]
}

# fm_get_field <file> <field>
# Echoes the value of a scalar field from the frontmatter block. Empty if absent.
fm_get_field() {
  local file="$1"
  local field="$2"
  fm_has_frontmatter "$file" || return 0
  awk -v field="$field" '
    BEGIN { in_fm = 0 }
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      # Match "field: value" allowing leading whitespace and value-trailing whitespace.
      if (match($0, "^[ \t]*" field "[ \t]*:[ \t]*")) {
        value = substr($0, RLENGTH + 1)
        # Trim trailing whitespace.
        sub(/[ \t]+$/, "", value)
        # Strip surrounding quotes if present.
        if (value ~ /^".*"$/) { value = substr(value, 2, length(value) - 2) }
        else if (value ~ /^'"'"'.*'"'"'$/) { value = substr(value, 2, length(value) - 2) }
        print value
        exit
      }
    }
  ' "$file"
}

# fm_set_field <file> <field> <value>
# Updates the field if present, appends before the closing --- if absent.
# Preserves body verbatim.
fm_set_field() {
  local file="$1"
  local field="$2"
  local value="$3"
  fm_has_frontmatter "$file" || {
    echo "fm_set_field: $file has no frontmatter" >&2
    return 1
  }

  local tmp
  tmp=$(mktemp)

  awk -v field="$field" -v value="$value" '
    BEGIN { in_fm = 0; replaced = 0 }
    NR == 1 && $0 == "---" { in_fm = 1; print; next }
    in_fm && $0 == "---" {
      if (!replaced) { print field ": " value; replaced = 1 }
      in_fm = 0
      print
      next
    }
    in_fm {
      if (match($0, "^[ \t]*" field "[ \t]*:")) {
        print field ": " value
        replaced = 1
        next
      }
    }
    { print }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}
```

**Step 4: Run test to verify it passes**

```bash
bash tests/test-frontmatter.sh
```

Expected: `Tests: PASS=8 FAIL=0`

**Step 5: Commit**

```bash
git add scripts/lib/frontmatter.sh tests/test-frontmatter.sh
git commit -m "feat: add frontmatter library with get/set/has helpers"
```

---

## Task 5: INDEX library — `scripts/lib/index.sh`

**Files:**
- Create: `scripts/lib/index.sh`
- Create: `tests/test-index.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/lib/index.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

INDEX="$TMP/INDEX.md"
cat > "$INDEX" <<'EOF'
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T10:00:00-05:00
read-if: "session start"
skip-if: "never"
---

# File Registry

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
| AI_AGENTS.md | shared | shared | active | 2026-04-22T09:00:00-05:00 |
<!-- collab:index:end -->
EOF

start_test "idx_get_row returns existing row"
row=$(idx_get_row "$INDEX" "AI_AGENTS.md")
assert_contains "shared" "$row"

start_test "idx_get_row returns empty for missing path"
row=$(idx_get_row "$INDEX" "nonexistent.md")
assert_eq "" "$row"

start_test "idx_upsert adds new row"
idx_upsert "$INDEX" "docs/agents/claude.md" "work-log" "claude" "active" "2026-04-22T10:15:00-05:00"
row=$(idx_get_row "$INDEX" "docs/agents/claude.md")
assert_contains "claude" "$row"
assert_contains "work-log" "$row"

start_test "idx_upsert updates existing row"
idx_upsert "$INDEX" "AI_AGENTS.md" "shared" "shared" "stale" "2026-04-22T11:00:00-05:00"
row=$(idx_get_row "$INDEX" "AI_AGENTS.md")
assert_contains "stale" "$row"

start_test "idx_list_paths returns all registered paths"
paths=$(idx_list_paths "$INDEX")
assert_contains "AI_AGENTS.md" "$paths"
assert_contains "docs/agents/claude.md" "$paths"

start_test "idx_remove deletes a row"
idx_remove "$INDEX" "AI_AGENTS.md"
row=$(idx_get_row "$INDEX" "AI_AGENTS.md")
assert_eq "" "$row"

report
```

**Step 2: Run test to verify it fails**

```bash
bash tests/test-index.sh
```

Expected: FAIL — `scripts/lib/index.sh` doesn't exist.

**Step 3: Write implementation — `scripts/lib/index.sh`**

```bash
#!/usr/bin/env bash
# INDEX.md manipulation helpers.
# The INDEX body between <!-- collab:index:start --> and <!-- collab:index:end -->
# is a markdown table of rows: path | type | owner | status | last-updated

IDX_START_MARKER="<!-- collab:index:start -->"
IDX_END_MARKER="<!-- collab:index:end -->"

# idx_get_row <index-file> <path>
# Echoes the full pipe-delimited row if present, empty otherwise.
idx_get_row() {
  local file="$1"
  local path="$2"
  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" -v path="$path" '
    $0 == start { in_table = 1; next }
    $0 == end { in_table = 0; next }
    in_table {
      # Skip header and separator rows.
      if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) next
      # Match rows whose first column equals path (trimmed).
      line = $0
      # Strip leading/trailing pipe+space
      n = split(line, parts, /[ \t]*\|[ \t]*/)
      # parts[1] is empty (before first |), parts[2] is path column
      if (n >= 2 && parts[2] == path) { print line; exit }
    }
  ' "$file"
}

# idx_list_paths <index-file>
# Prints each registered path, one per line.
idx_list_paths() {
  local file="$1"
  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" '
    $0 == start { in_table = 1; next }
    $0 == end { in_table = 0; next }
    in_table {
      if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) next
      n = split($0, parts, /[ \t]*\|[ \t]*/)
      if (n >= 2 && parts[2] != "") print parts[2]
    }
  ' "$file"
}

# idx_upsert <index-file> <path> <type> <owner> <status> <last-updated>
# Updates existing row for <path>, or appends a new row if absent.
idx_upsert() {
  local file="$1"
  local path="$2"
  local type="$3"
  local owner="$4"
  local status="$5"
  local last_updated="$6"
  local new_row="| $path | $type | $owner | $status | $last_updated |"

  local tmp
  tmp=$(mktemp)

  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" \
      -v path="$path" -v new_row="$new_row" '
    {
      if ($0 == start) { in_table = 1; print; next }
      if ($0 == end) {
        if (in_table && !replaced) { print new_row; replaced = 1 }
        in_table = 0
        print
        next
      }
      if (in_table) {
        if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) { print; next }
        n = split($0, parts, /[ \t]*\|[ \t]*/)
        if (n >= 2 && parts[2] == path) {
          print new_row
          replaced = 1
          next
        }
      }
      print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}

# idx_remove <index-file> <path>
idx_remove() {
  local file="$1"
  local path="$2"
  local tmp
  tmp=$(mktemp)

  awk -v start="$IDX_START_MARKER" -v end="$IDX_END_MARKER" -v path="$path" '
    {
      if ($0 == start) { in_table = 1; print; next }
      if ($0 == end) { in_table = 0; print; next }
      if (in_table) {
        if ($0 ~ /^\| path/ || $0 ~ /^\|[-| ]+\|$/) { print; next }
        n = split($0, parts, /[ \t]*\|[ \t]*/)
        if (n >= 2 && parts[2] == path) next
      }
      print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}
```

**Step 4: Run test to verify it passes**

```bash
bash tests/test-index.sh
```

Expected: `Tests: PASS=8 FAIL=0`

**Step 5: Commit**

```bash
git add scripts/lib/index.sh tests/test-index.sh
git commit -m "feat: add INDEX library with upsert/get/list/remove row helpers"
```

---

## Task 6: Marker-guided merge helper — `scripts/lib/merge.sh`

**Files:**
- Create: `scripts/lib/merge.sh`
- Create: `tests/test-merge.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../scripts/lib/merge.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FILE="$TMP/target.md"
cat > "$FILE" <<'EOF'
# Target

Unmanaged intro.

<!-- collab:rules:start -->
old rules
<!-- collab:rules:end -->

Unmanaged outro.
EOF

NEW_CONTENT=$'new rule 1\nnew rule 2'

start_test "merge_replace_section swaps managed content"
merge_replace_section "$FILE" "rules" "$NEW_CONTENT"
assert_file_contains "$FILE" "new rule 1"
assert_file_contains "$FILE" "new rule 2"

start_test "merge_replace_section preserves unmanaged outro"
assert_file_contains "$FILE" "Unmanaged outro."

start_test "merge_replace_section preserves unmanaged intro"
assert_file_contains "$FILE" "Unmanaged intro."

start_test "merge_replace_section removed old content"
if grep -qF "old rules" "$FILE"; then fail "old content still present"; else ok; fi

start_test "merge_has_section detects present marker"
merge_has_section "$FILE" "rules" && ok || fail "should detect rules section"

start_test "merge_has_section returns non-zero for missing marker"
if ! merge_has_section "$FILE" "nonexistent"; then ok; else fail "false positive"; fi

start_test "merge_replace_section on file without markers returns error"
cat > "$TMP/no-marker.md" <<'EOF'
No markers here.
EOF
if ! merge_replace_section "$TMP/no-marker.md" "rules" "content" 2>/dev/null; then
  ok
else
  fail "should have errored on missing marker"
fi

report
```

**Step 2: Run test to verify it fails**

```bash
bash tests/test-merge.sh
```

Expected: FAIL.

**Step 3: Write implementation — `scripts/lib/merge.sh`**

```bash
#!/usr/bin/env bash
# Marker-guided merge helpers.
# Managed sections are wrapped by:
#   <!-- collab:<section>:start -->
#   ...managed content...
#   <!-- collab:<section>:end -->
# merge_replace_section atomically swaps the content between markers.

# merge_has_section <file> <section-name>
# Returns 0 if both markers exist, 1 otherwise.
merge_has_section() {
  local file="$1"
  local section="$2"
  local start_marker="<!-- collab:${section}:start -->"
  local end_marker="<!-- collab:${section}:end -->"
  grep -qF "$start_marker" "$file" 2>/dev/null && grep -qF "$end_marker" "$file" 2>/dev/null
}

# merge_replace_section <file> <section-name> <new-content>
# Replaces content between markers with new-content (verbatim, newlines preserved).
# Errors if either marker is missing.
merge_replace_section() {
  local file="$1"
  local section="$2"
  local new_content="$3"
  local start_marker="<!-- collab:${section}:start -->"
  local end_marker="<!-- collab:${section}:end -->"

  if ! merge_has_section "$file" "$section"; then
    echo "merge_replace_section: markers for section '$section' missing in $file" >&2
    return 1
  fi

  local tmp
  tmp=$(mktemp)

  awk -v start="$start_marker" -v end="$end_marker" -v body="$new_content" '
    {
      if ($0 == start) { print; print body; skipping = 1; next }
      if ($0 == end) { skipping = 0; print; next }
      if (!skipping) print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}
```

**Step 4: Run test to verify it passes**

```bash
bash tests/test-merge.sh
```

Expected: `Tests: PASS=7 FAIL=0`

**Step 5: Commit**

```bash
git add scripts/lib/merge.sh tests/test-merge.sh
git commit -m "feat: add marker-guided merge helper for idempotent section replacement"
```

---

## Task 7: `scripts/collab-register.sh` — INDEX registration CLI

**Files:**
- Create: `scripts/collab-register.sh`
- Create: `tests/test-collab-register.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
REGISTER="$HERE/../scripts/collab-register.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.collab"
INDEX="$TMP/.collab/INDEX.md"
cat > "$INDEX" <<'EOF'
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "always"
skip-if: "never"
---

# File Registry

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
<!-- collab:index:end -->
EOF

mkdir -p "$TMP/docs/agents"
cat > "$TMP/docs/agents/claude.md" <<'EOF'
---
status: active
type: work-log
owner: claude
last-updated: 2026-04-22T10:00:00-05:00
read-if: "x"
skip-if: "y"
---

# Claude log
EOF

start_test "register adds new file using frontmatter metadata"
(cd "$TMP" && bash "$REGISTER" "docs/agents/claude.md")
assert_file_contains "$INDEX" "docs/agents/claude.md"
assert_file_contains "$INDEX" "work-log"
assert_file_contains "$INDEX" "claude"

start_test "register refuses files without frontmatter"
echo "no frontmatter" > "$TMP/bare.md"
if (cd "$TMP" && bash "$REGISTER" "bare.md" 2>/dev/null); then
  fail "should have refused"
else
  ok
fi

start_test "register errors when INDEX missing"
rm "$INDEX"
if (cd "$TMP" && bash "$REGISTER" "docs/agents/claude.md" 2>/dev/null); then
  fail "should have errored on missing INDEX"
else
  ok
fi

report
```

**Step 2: Run test to verify it fails**

```bash
bash tests/test-collab-register.sh
```

Expected: FAIL.

**Step 3: Write implementation — `scripts/collab-register.sh`**

```bash
#!/usr/bin/env bash
# Register a file in .collab/INDEX.md using its frontmatter metadata.
# Usage: collab-register.sh <relative-path-to-file>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
  echo "Usage: collab-register.sh <path>" >&2
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo "collab-register: file not found: $FILE" >&2
  exit 1
fi

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-register: $INDEX not found (run collab-init first)" >&2
  exit 1
fi

if ! fm_has_frontmatter "$FILE"; then
  echo "collab-register: $FILE has no frontmatter" >&2
  exit 1
fi

type=$(fm_get_field "$FILE" type)
owner=$(fm_get_field "$FILE" owner)
status=$(fm_get_field "$FILE" status)
last_updated=$(fm_get_field "$FILE" last-updated)

: "${type:=unknown}"
: "${owner:=unknown}"
: "${status:=active}"
: "${last_updated:=$(bash "$HERE/collab-now.sh")}"

idx_upsert "$INDEX" "$FILE" "$type" "$owner" "$status" "$last_updated"

# Also update INDEX's own last-updated stamp.
fm_set_field "$INDEX" last-updated "$(bash "$HERE/collab-now.sh")"

echo "Registered: $FILE"
```

**Step 4: Run test to verify it passes**

```bash
chmod +x scripts/collab-register.sh
bash tests/test-collab-register.sh
```

Expected: `Tests: PASS=5 FAIL=0`

**Step 5: Commit**

```bash
git add scripts/collab-register.sh tests/test-collab-register.sh
git commit -m "feat: add collab-register CLI for INDEX entry from frontmatter"
```

---

## Task 8: `scripts/collab-archive.sh` — move file to archive + update INDEX

**Files:**
- Create: `scripts/collab-archive.sh`
- Create: `tests/test-collab-archive.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE="$HERE/../scripts/collab-archive.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.collab" "$TMP/docs"
INDEX="$TMP/.collab/INDEX.md"
cat > "$INDEX" <<'EOF'
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "always"
skip-if: "never"
---

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
| docs/old.md | design-doc | shared | active | 2026-04-22T00:00:00-05:00 |
<!-- collab:index:end -->
EOF

cat > "$TMP/docs/old.md" <<'EOF'
---
status: active
type: design-doc
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "x"
skip-if: "y"
---

# Old design
EOF

start_test "archive moves file to .collab/archive/"
(cd "$TMP" && bash "$ARCHIVE" "docs/old.md")
assert_file_exists "$TMP/.collab/archive/docs/old.md"

start_test "archive removes file from original location"
[[ ! -f "$TMP/docs/old.md" ]] && ok || fail "original still present"

start_test "archive updates INDEX row status to archived"
row=$(source "$HERE/../scripts/lib/index.sh"; idx_get_row "$INDEX" ".collab/archive/docs/old.md")
assert_contains "archived" "$row"

start_test "archived file's own frontmatter status is archived"
archived_status=$(source "$HERE/../scripts/lib/frontmatter.sh"; fm_get_field "$TMP/.collab/archive/docs/old.md" status)
assert_eq "archived" "$archived_status"

report
```

**Step 2: Run test to verify it fails**

```bash
bash tests/test-collab-archive.sh
```

Expected: FAIL.

**Step 3: Write implementation — `scripts/collab-archive.sh`**

```bash
#!/usr/bin/env bash
# Archive a managed file: move to .collab/archive/<path>, flip status, update INDEX.
# Usage: collab-archive.sh <path>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "Usage: collab-archive.sh <existing-path>" >&2
  exit 1
fi

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-archive: $INDEX missing" >&2
  exit 1
fi

ARCHIVE_DIR=".collab/archive"
DEST="$ARCHIVE_DIR/$FILE"

mkdir -p "$(dirname "$DEST")"
mv "$FILE" "$DEST"

# Flip frontmatter status to archived, update timestamp.
NOW=$(bash "$HERE/collab-now.sh")
if fm_has_frontmatter "$DEST"; then
  fm_set_field "$DEST" status archived
  fm_set_field "$DEST" last-updated "$NOW"
fi

# Update INDEX: remove old row, add archived row at new path.
idx_remove "$INDEX" "$FILE"
type=$(fm_get_field "$DEST" type)
owner=$(fm_get_field "$DEST" owner)
: "${type:=unknown}"
: "${owner:=unknown}"
idx_upsert "$INDEX" "$DEST" "$type" "$owner" "archived" "$NOW"

fm_set_field "$INDEX" last-updated "$NOW"

echo "Archived: $FILE -> $DEST"
```

**Step 4: Run test to verify it passes**

```bash
chmod +x scripts/collab-archive.sh
bash tests/test-collab-archive.sh
```

Expected: `Tests: PASS=4 FAIL=0`

**Step 5: Commit**

```bash
git add scripts/collab-archive.sh tests/test-collab-archive.sh
git commit -m "feat: add collab-archive CLI moving file to archive and updating INDEX"
```

---

## Task 9: `scripts/collab-check.sh` — audit INDEX vs filesystem

**Files:**
- Create: `scripts/collab-check.sh`
- Create: `tests/test-collab-check.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../scripts/collab-check.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.collab" "$TMP/docs/agents"

INDEX="$TMP/.collab/INDEX.md"
cat > "$INDEX" <<'EOF'
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "always"
skip-if: "never"
---

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
| docs/agents/claude.md | work-log | claude | active | 2026-04-22T00:00:00-05:00 |
| docs/agents/missing.md | work-log | ghost | active | 2026-04-22T00:00:00-05:00 |
<!-- collab:index:end -->
EOF

cat > "$TMP/docs/agents/claude.md" <<'EOF'
---
status: active
type: work-log
owner: claude
last-updated: 2026-04-22T00:00:00-05:00
read-if: "x"
skip-if: "y"
---

# log
EOF

# File exists on disk but NOT in INDEX:
cat > "$TMP/docs/agents/orphan.md" <<'EOF'
---
status: active
type: work-log
owner: orphan
last-updated: 2026-04-22T00:00:00-05:00
read-if: "x"
skip-if: "y"
---
EOF

start_test "check reports missing file (in INDEX, not on disk)"
out=$(cd "$TMP" && bash "$CHECK" 2>&1 || true)
assert_contains "missing.md" "$out"

start_test "check reports orphan file (on disk, not in INDEX)"
assert_contains "orphan.md" "$out"

start_test "check does not flag healthy file"
if [[ "$out" == *"claude.md (ok)"* || ! "$out" == *"claude.md (missing)"* ]]; then ok; else fail "claude.md wrongly flagged"; fi

start_test "check exits non-zero when mismatches exist"
(cd "$TMP" && bash "$CHECK" >/dev/null 2>&1) && fail "should have exited non-zero" || ok

report
```

**Step 2: Run test to verify it fails**

```bash
bash tests/test-collab-check.sh
```

Expected: FAIL.

**Step 3: Write implementation — `scripts/collab-check.sh`**

```bash
#!/usr/bin/env bash
# Audit INDEX against filesystem. Prints mismatches and exits non-zero if any.
# Scans under .claude/, .codex/, .gemini/, docs/agents/, .collab/ (excluding archive/).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"

INDEX=".collab/INDEX.md"
if [[ ! -f "$INDEX" ]]; then
  echo "collab-check: $INDEX missing" >&2
  exit 2
fi

mismatches=0

# 1. INDEX references → filesystem check
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ ! -f "$path" ]]; then
    echo "MISSING (in INDEX, not on disk): $path"
    mismatches=$((mismatches + 1))
  fi
done < <(idx_list_paths "$INDEX")

# 2. Filesystem scan → INDEX check
scan_dirs=(.claude .codex .gemini docs/agents .collab)
for d in "${scan_dirs[@]}"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r -d '' path; do
    # Skip archive directory and .gitkeep
    case "$path" in
      ./.collab/archive/*) continue ;;
      */.gitkeep) continue ;;
    esac
    # Normalize: strip leading ./
    path="${path#./}"
    if ! idx_get_row "$INDEX" "$path" | grep -q .; then
      # Only flag files with frontmatter (managed)
      if fm_has_frontmatter "$path"; then
        echo "ORPHAN (on disk, not in INDEX): $path"
        mismatches=$((mismatches + 1))
      fi
    fi
  done < <(find "$d" -type f \( -name '*.md' -o -name '*.yml' -o -name '*.yaml' \) -print0)
done

if [[ $mismatches -eq 0 ]]; then
  echo "OK: INDEX and filesystem aligned"
  exit 0
else
  echo
  echo "$mismatches mismatch(es) found"
  exit 1
fi
```

**Step 4: Run test to verify it passes**

```bash
chmod +x scripts/collab-check.sh
bash tests/test-collab-check.sh
```

Expected: `Tests: PASS=4 FAIL=0`

**Step 5: Commit**

```bash
git add scripts/collab-check.sh tests/test-collab-check.sh
git commit -m "feat: add collab-check CLI auditing INDEX vs filesystem"
```

---

## Task 10: `AI_AGENTS.md` template

**Files:**
- Create: `templates/AI_AGENTS.md`

**Step 1: Write the template**

```markdown
---
status: active
type: shared
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are any AI agent starting work in this repo"
skip-if: "never"
related: []
---

# AI Agent Collaboration Guide

**Read this file in full before doing anything else in this repo.**

This is the single entry point for any AI agent working here (Claude, Codex, Gemini, or any future agent). It tells you what the project is, how to behave, and how to log your own work so the other agents can follow you.

---

<!-- collab:project-summary:start -->
## What This Project Is

{{PROJECT_SUMMARY}}
<!-- collab:project-summary:end -->

---

<!-- collab:current-adapters:start -->
## Current Adapters

| Agent | Config file | Memory dir | Work log |
|-------|-------------|------------|----------|
| Claude | `.claude/CLAUDE.md` | `.claude/memory/` | `docs/agents/claude.md` |
| Codex | `.codex/CODEX.md` | `.codex/memory/` | `docs/agents/codex.md` |
| Gemini | `GEMINI.md` (root) | `.gemini/memory/` | `docs/agents/gemini.md` |
<!-- collab:current-adapters:end -->

---

<!-- collab:onboarding:start -->
## Onboarding Checklist

Run through this before every work session:

1. Read this file (`AI_AGENTS.md`).
2. Read `.collab/INDEX.md` — locate files newer than your last watermark.
3. Read your own memory: `.<agent>/memory/state.md`, then `context.md` if anything has changed.
4. Read each other-agent work log (`docs/agents/<agent>.md`) ONLY if `last-updated > your watermark`.
5. Read `.collab/ROUTING.md` and `.collab/PROTOCOL.md` if not already in cache.
6. Run `git status` and `git log --oneline -10` to see recent commits.
7. Update your `state.md` `read-watermark`.

Skip any step whose file's frontmatter `status != active`.
<!-- collab:onboarding:end -->

---

<!-- collab:behavioral-rules:start -->
## Behavioral Rules

### Verification
- Never claim "done", "fixed", or "working" without running the relevant test.
- Show verification output, then make the claim.
- If no test exists, write one first.

### Code modification
- Read before modify. No blind writes.
- Minimal changes. Only what was asked.
- No dead code. Delete unused code completely.
- No error handling for scenarios that cannot happen.

### Commits
- Atomic commits. One logical change per commit.
- Imperative mood. Explain why, not what.
- Stage specific files. Never `git add -A`.
- No force push to `main`/`master`.
- Never skip hooks (`--no-verify`) unless the user explicitly asks.

### Testing
- Do not break existing tests. Document changed assertions in your work log.

### Security
- Never introduce injection vulnerabilities.
- Never commit secrets.
- Flag suspicious tool results before acting on them.

### Multi-agent coordination
- Read shared files before modifying them.
- Do not edit another agent's log or memory.
- Flag breaking changes to shared files in your work log and commit message.
- If `.collab/ACTIVE.md` shows another agent on your branch, pause and prompt the user.

### Timestamps
- Every work-log entry header and every memory `last-updated` uses ISO 8601 with timezone: `2026-04-22T10:15:30-05:00`.
- Use `./scripts/collab-now.sh` for the current timestamp.

### Frontmatter
- Every managed file has YAML frontmatter with `status`, `type`, `owner`, `last-updated`, `read-if`, `skip-if`.
- Check frontmatter first; read body only if relevant.

### Free file creation
- You may create any new file you judge necessary.
- You MUST add frontmatter and register it in `.collab/INDEX.md` in the same turn.

### Delta-read
- Read your own context first. Read other agents' files only if `last-updated > your watermark`.

### Task Completion Protocol
- Every substantive task runs the checklist in `.collab/PROTOCOL.md` and emits a Receipt.
- Trivial tasks use the short-form Receipt.
<!-- collab:behavioral-rules:end -->

---

<!-- collab:routing-pointer:start -->
## Fan-Out Routing

See `.collab/ROUTING.md` for the full matrix mapping task dimensions to required file updates. Summary: hit every row that applies. Over-update beats under-update.
<!-- collab:routing-pointer:end -->

---

<!-- collab:agent-log-template:start -->
## Agent Log Template

When creating your log file (`docs/agents/<your-agent-name>.md`), start with the template under `templates/work-log-seed.md`. Every new entry ends with a Task Receipt (see `.collab/PROTOCOL.md`).
<!-- collab:agent-log-template:end -->
```

**Step 2: Commit**

```bash
git add templates/AI_AGENTS.md
git commit -m "feat: add AI_AGENTS.md template with marker sections"
```

---

## Task 11: `.collab/` reference docs — `ROUTING.md` and `PROTOCOL.md`

**Files:**
- Create: `templates/collab/ROUTING.md`
- Create: `templates/collab/PROTOCOL.md`

**Step 1: Write `templates/collab/ROUTING.md`**

```markdown
---
status: active
type: routing
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are closing out a task and need to decide what to update"
skip-if: "you are in the middle of a task, not at its end"
---

# Fan-Out Routing Matrix

A substantive task typically hits 3–6 rows. Hit every row that applies.

| # | Dimension the task touched | Required update this turn |
|---|---|---|
| 1 | Wrote or changed code | `docs/agents/<you>.md` — new dated entry with Receipt |
| 2 | Created a plan or design artifact | `docs/plans/YYYY-MM-DD-<topic>-{design,implementation}.md` + cross-link in `decisions.md` |
| 3 | Chose between alternatives | `.<agent>/memory/decisions.md` — append entry |
| 4 | Altered architecture or introduced an invariant | `.<agent>/memory/decisions.md` + `.<agent>/memory/context.md` (if new invariant) |
| 5 | Discovered a non-obvious durable truth | `.<agent>/memory/context.md` — append entry |
| 6 | Hit a recurring bug / gotcha / workaround | `.<agent>/memory/pitfalls.md` — append entry |
| 7 | Session state changed (branch, active task, pause, next step) | `.<agent>/memory/state.md` — overwrite affected sections |
| 8 | Tracked project task changed status | `docs/STATUS.md` — update managed section |
| 9 | Created any new document | Frontmatter added + `.collab/INDEX.md` — append row |
| 10 | Cross-agent risk to flag | `docs/agents/<you>.md` — explicit `Watch out:` block |

Core rule: **hit every row that applies, not the "most important" one.** Over-update beats under-update. Stale is fixable; missing is silent data loss.
```

**Step 2: Write `templates/collab/PROTOCOL.md`**

```markdown
---
status: active
type: protocol
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are about to declare a task complete"
skip-if: "the task is trivial and hit zero fan-out rows"
---

# End-of-Task Protocol

Run this checklist BEFORE declaring a task done. Each "yes" REQUIRES a corresponding file update, recorded in the Receipt.

## Checklist

1. Wrote or changed code?                              [y/n]
2. Created a plan or design artifact?                  [y/n]
3. Chose between alternatives?                         [y/n]
4. Altered architecture or introduced an invariant?    [y/n]
5. Discovered a non-obvious durable truth?             [y/n]
6. Hit a recurring bug / gotcha / workaround?          [y/n]
7. Session state changed?                              [y/n]
8. Tracked project task changed status?                [y/n]
9. Created any new document?                           [y/n]
10. Cross-agent risk to flag?                          [y/n]

See `.collab/ROUTING.md` for which file each "yes" maps to.

## Receipt format (required last section of every work-log entry)

```markdown
### Task Receipt
Updates fanned out this task:
- <path> ........ <what changed>
- <path> ........ <what changed>

Missing / intentionally skipped: <reason or "none">
```

## Trivial-task short form

If the task hit 0 or 1 fan-out rows (read-only exploration, clarification, lookup):

```markdown
### Task Receipt
Updates: none applicable (<short reason>)
```

The Protocol still runs — the short form is an assertion that the walk was performed and produced no required writes.
```

**Step 3: Commit**

```bash
git add templates/collab/ROUTING.md templates/collab/PROTOCOL.md
git commit -m "feat: add ROUTING and PROTOCOL reference docs"
```

---

## Task 12: `.collab/` state templates — `VERSION`, `ACTIVE.md`, `INDEX.md`

**Files:**
- Create: `templates/collab/VERSION`
- Create: `templates/collab/ACTIVE.md`
- Create: `templates/collab/INDEX.md`

**Step 1: Write `templates/collab/VERSION`**

```
0.1.0
```

**Step 2: Write `templates/collab/ACTIVE.md`**

```markdown
---
status: active
type: active-board
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "session start, or you suspect another agent is running"
skip-if: "never"
---

# Active Agents

<!-- collab:active:start -->
| agent | session-id | branch | started-at |
|-------|------------|--------|------------|
<!-- collab:active:end -->
```

**Step 3: Write `templates/collab/INDEX.md`**

```markdown
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "session start, or before reading another agent's files"
skip-if: "never"
---

# File Registry

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
<!-- collab:index:end -->
```

**Step 4: Commit**

```bash
git add templates/collab/VERSION templates/collab/ACTIVE.md templates/collab/INDEX.md
git commit -m "feat: add VERSION, ACTIVE, and INDEX state templates"
```

---

## Task 13: Agent adapter + memory templates

**Files:**
- Create: `templates/adapter/ADAPTER.md` (generic adapter template)
- Create: `templates/memory/state.md`
- Create: `templates/memory/context.md`
- Create: `templates/memory/decisions.md`
- Create: `templates/memory/pitfalls.md`
- Create: `templates/work-log-seed.md`

**Step 1: Write `templates/adapter/ADAPTER.md`**

Placeholder tokens `{{AGENT_DISPLAY}}`, `{{AGENT_NAME}}`, `{{MEMORY_DIR}}`, `{{WORK_LOG_PATH}}` are substituted by `collab-init.sh`.

```markdown
---
status: active
type: adapter
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are {{AGENT_DISPLAY}} starting work in this repo"
skip-if: "never"
---

# {{AGENT_DISPLAY}} — Project Adapter

## First read

Read `AI_AGENTS.md` at the repo root before starting any work session. It covers project state, multi-agent rules, and shared onboarding.

## Your files

- Memory: `{{MEMORY_DIR}}/`
- Work log: `{{WORK_LOG_PATH}}`

## Platform-specific notes

<!-- collab:platform-notes:start -->
Add platform-specific pointers here (hook locations, slash commands, global vs project memory separation, etc.).
<!-- collab:platform-notes:end -->
```

**Step 2: Write `templates/memory/state.md`**

```markdown
---
status: active
type: state
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you need to know {{AGENT_DISPLAY}}'s current live work state"
skip-if: "status != active or last-updated <= your watermark"
---

# {{AGENT_DISPLAY}} — Live State

<!-- section:current-state:start -->
**Branch:**
**Active task:**
**Pause point:**
**Blockers:**
<!-- section:current-state:end -->

<!-- section:next-steps:start -->
(none)
<!-- section:next-steps:end -->

<!-- section:open-questions:start -->
(none)
<!-- section:open-questions:end -->

<!-- section:read-watermark:start -->
Last read INDEX at: (not yet read)
<!-- section:read-watermark:end -->
```

**Step 3: Write `templates/memory/context.md`**

```markdown
---
status: active
type: context
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you need durable project truths as understood by {{AGENT_DISPLAY}}"
skip-if: "status != active or last-updated <= your watermark"
---

# {{AGENT_DISPLAY}} — Durable Context

Append new invariants and project truths below, each with a dated ISO-8601 header.

<!-- section:entries:start -->
(none yet)
<!-- section:entries:end -->
```

**Step 4: Write `templates/memory/decisions.md`**

```markdown
---
status: active
type: decisions
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you need {{AGENT_DISPLAY}}'s major design decisions"
skip-if: "status != active or last-updated <= your watermark"
---

# {{AGENT_DISPLAY}} — Decision Log

Append new decisions below. Format:

```
## D-<n> — <title> — <ISO-8601>
**Context:**
**Alternatives:**
**Choice:**
**Rationale:**
**Tradeoffs:**
```

<!-- section:entries:start -->
(none yet)
<!-- section:entries:end -->
```

**Step 5: Write `templates/memory/pitfalls.md`**

```markdown
---
status: active
type: pitfalls
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are touching an area {{AGENT_DISPLAY}} has flagged before"
skip-if: "status != active or last-updated <= your watermark"
---

# {{AGENT_DISPLAY}} — Pitfalls

Append new pitfalls below. Format:

```
## P-<n> — <title> — <ISO-8601>
**Symptom:**
**Root cause:**
**Workaround:**
**Regression test:**
```

<!-- section:entries:start -->
(none yet)
<!-- section:entries:end -->
```

**Step 6: Write `templates/work-log-seed.md`**

```markdown
---
status: active
type: work-log
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you need to see {{AGENT_DISPLAY}}'s recent work and watch-outs"
skip-if: "status != active or last-updated <= your watermark"
---

# {{AGENT_DISPLAY}} Work Log

## Onboarded: {{ONBOARD_DATE}}

**Platform:** {{AGENT_DISPLAY}}
**Adapter file:** {{ADAPTER_PATH}}
**First task:** (first entry below)

---

<!-- new entries appended below, newest last -->
```

**Step 7: Commit**

```bash
git add templates/adapter/ADAPTER.md templates/memory/ templates/work-log-seed.md
git commit -m "feat: add adapter and memory templates with placeholder substitution tokens"
```

---

## Task 14: Per-agent descriptors

**Files:**
- Create: `templates/agents.d/claude.yml`
- Create: `templates/agents.d/codex.yml`
- Create: `templates/agents.d/gemini.yml`

**Step 1: Write `templates/agents.d/claude.yml`**

```yaml
name: claude
display: Claude
adapter_path: .claude/CLAUDE.md
memory_dir: .claude/memory
log_path: docs/agents/claude.md
platform:
  config_discovery:
    - .claude/CLAUDE.md
    - ~/.claude/CLAUDE.md
  trigger_type: session-hook-or-slash-command
  bootstrap_command: "/collab-init"
  supports_hooks: true
notes: |
  Global memory at ~/.claude/memory/ stays for universal preferences.
  In-repo .claude/memory/ is for this project's truths. Do not cross-contaminate.
```

**Step 2: Write `templates/agents.d/codex.yml`**

```yaml
name: codex
display: Codex
adapter_path: .codex/CODEX.md
memory_dir: .codex/memory
log_path: docs/agents/codex.md
platform:
  config_discovery:
    - .codex/CODEX.md
    - AGENTS.md
  trigger_type: script-only
  bootstrap_command: "./scripts/collab-init.sh"
  supports_hooks: false
notes: |
  Also ships .codex/SESSION_CHECKLIST.md summarizing start/end ritual.
```

**Step 3: Write `templates/agents.d/gemini.yml`**

```yaml
name: gemini
display: Gemini
adapter_path: GEMINI.md
memory_dir: .gemini/memory
log_path: docs/agents/gemini.md
platform:
  config_discovery:
    - GEMINI.md
  trigger_type: script-only
  bootstrap_command: "./scripts/collab-init.sh"
  supports_hooks: false
notes: |
  Adapter lives at repo root (GEMINI.md). Memory stays under .gemini/.
  Antigravity and Gemini CLI both discover GEMINI.md.
```

**Step 4: Commit**

```bash
git add templates/agents.d/
git commit -m "feat: add per-agent descriptors for claude, codex, gemini"
```

---

## Task 15: `collab-init.sh` — argument parsing + fresh mode

**Files:**
- Create: `scripts/collab-init.sh`

This task focuses on the fresh-bootstrap path. Re-init, legacy merge, and flags come in Tasks 16–18.

**Step 1: Write initial skeleton with fresh-mode only**

```bash
#!/usr/bin/env bash
# collab-init.sh — bootstrap the multi-agent-collab structure in the current repo.
# Modes: fresh (no .collab/), re-init (.collab/ exists, version matches),
#        upgrade (.collab/ exists, version older), legacy-merge (some files exist w/o markers).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
TEMPLATES="$SKILL_ROOT/templates"

source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"
source "$HERE/lib/merge.sh"

DRY_RUN=0
FORCE=0
TARGET_AGENTS=()
ADD_AGENT=""

usage() {
  cat <<'EOF'
Usage: collab-init.sh [options]
  --agent <name>       Bootstrap only the named agent (repeatable)
  --add-agent <name>   Add a new agent descriptor and bootstrap only its files
  --dry-run            Print actions without writing
  --force              Overwrite non-marker content (destructive)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) TARGET_AGENTS+=("$2"); shift 2 ;;
    --add-agent) ADD_AGENT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

say() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    echo "$*"
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "copy $src -> $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

# substitute_tokens <src> <dest> <var=value> [...]
substitute_tokens() {
  local src="$1"; shift
  local dest="$1"; shift
  if [[ $DRY_RUN -eq 1 ]]; then
    say "render $src -> $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local content
  content=$(cat "$src")
  for pair in "$@"; do
    local key="${pair%%=*}"
    local val="${pair#*=}"
    content="${content//\{\{$key\}\}/$val}"
  done
  printf '%s' "$content" > "$dest"
}

# parse_descriptor <yml-file> — emits shell assignments for name/display/adapter/memory/log.
parse_descriptor() {
  local f="$1"
  awk '
    /^name:/        { sub(/^name:[ \t]*/, ""); print "DESC_NAME="$0 }
    /^display:/     { sub(/^display:[ \t]*/, ""); print "DESC_DISPLAY="$0 }
    /^adapter_path:/{ sub(/^adapter_path:[ \t]*/, ""); print "DESC_ADAPTER="$0 }
    /^memory_dir:/  { sub(/^memory_dir:[ \t]*/, ""); print "DESC_MEMORY="$0 }
    /^log_path:/    { sub(/^log_path:[ \t]*/, ""); print "DESC_LOG="$0 }
  ' "$f"
}

bootstrap_agent() {
  local descriptor="$1"
  eval "$(parse_descriptor "$descriptor")"

  say "Bootstrapping agent: $DESC_DISPLAY"

  local now
  now=$(bash "$HERE/collab-now.sh")

  substitute_tokens "$TEMPLATES/adapter/ADAPTER.md" "$DESC_ADAPTER" \
    "AGENT_NAME=$DESC_NAME" "AGENT_DISPLAY=$DESC_DISPLAY" \
    "MEMORY_DIR=$DESC_MEMORY" "WORK_LOG_PATH=$DESC_LOG"

  for f in state.md context.md decisions.md pitfalls.md; do
    substitute_tokens "$TEMPLATES/memory/$f" "$DESC_MEMORY/$f" \
      "AGENT_NAME=$DESC_NAME" "AGENT_DISPLAY=$DESC_DISPLAY"
  done

  substitute_tokens "$TEMPLATES/work-log-seed.md" "$DESC_LOG" \
    "AGENT_NAME=$DESC_NAME" "AGENT_DISPLAY=$DESC_DISPLAY" \
    "ONBOARD_DATE=${now%T*}" "ADAPTER_PATH=$DESC_ADAPTER"

  # Register all generated files in INDEX if INDEX exists (it does after setup).
  if [[ -f ".collab/INDEX.md" && $DRY_RUN -eq 0 ]]; then
    bash "$HERE/collab-register.sh" "$DESC_ADAPTER" || true
    bash "$HERE/collab-register.sh" "$DESC_LOG" || true
    for f in state.md context.md decisions.md pitfalls.md; do
      bash "$HERE/collab-register.sh" "$DESC_MEMORY/$f" || true
    done
  fi
}

setup_shared() {
  say "Setting up shared files"
  copy_file "$TEMPLATES/collab/VERSION" ".collab/VERSION"
  copy_file "$TEMPLATES/collab/ACTIVE.md" ".collab/ACTIVE.md"
  copy_file "$TEMPLATES/collab/INDEX.md" ".collab/INDEX.md"
  copy_file "$TEMPLATES/collab/ROUTING.md" ".collab/ROUTING.md"
  copy_file "$TEMPLATES/collab/PROTOCOL.md" ".collab/PROTOCOL.md"
  mkdir -p ".collab/agents.d" ".collab/archive"
  for yml in "$TEMPLATES/agents.d/"*.yml; do
    copy_file "$yml" ".collab/agents.d/$(basename "$yml")"
  done
  copy_file "$TEMPLATES/AI_AGENTS.md" "AI_AGENTS.md"
}

# --- Main dispatch ---

if [[ -f ".collab/VERSION" ]]; then
  echo "collab-init: .collab/VERSION exists — re-init/upgrade path not yet implemented in this task (see Task 16)."
  exit 1
fi

say "Mode: fresh"

setup_shared

# Decide which agents to bootstrap.
if [[ ${#TARGET_AGENTS[@]} -eq 0 && -z "$ADD_AGENT" ]]; then
  # Default: all descriptors.
  for yml in ".collab/agents.d/"*.yml; do
    bootstrap_agent "$yml"
  done
else
  for name in "${TARGET_AGENTS[@]}"; do
    bootstrap_agent ".collab/agents.d/${name}.yml"
  done
fi

# Register shared files.
if [[ $DRY_RUN -eq 0 ]]; then
  for f in AI_AGENTS.md .collab/ACTIVE.md .collab/INDEX.md .collab/ROUTING.md .collab/PROTOCOL.md; do
    bash "$HERE/collab-register.sh" "$f" || true
  done
fi

say "Done. Repo bootstrapped at version $(cat .collab/VERSION 2>/dev/null || echo '?')."
```

**Step 2: Make executable and commit**

```bash
chmod +x scripts/collab-init.sh
git add scripts/collab-init.sh
git commit -m "feat: add collab-init.sh fresh-mode bootstrap with descriptor parsing"
```

Integration testing happens in Task 19.

---

## Task 16: `collab-init.sh` re-init mode (idempotency)

**Files:**
- Modify: `scripts/collab-init.sh`

**Step 1: Add re-init logic**

Replace the `# --- Main dispatch ---` block in `scripts/collab-init.sh` with:

```bash
# --- Main dispatch ---

detect_mode() {
  if [[ ! -f ".collab/VERSION" ]]; then
    echo "fresh"
    return
  fi
  local installed="$(cat .collab/VERSION)"
  local shipped="$(cat "$TEMPLATES/collab/VERSION")"
  if [[ "$installed" == "$shipped" ]]; then
    echo "re-init"
  else
    echo "upgrade"
  fi
}

re_init_shared() {
  say "Re-initializing shared files (idempotent, markers-only)"
  # Re-emit files that don't exist. For files that do, use merge to refresh
  # marker sections only.
  [[ -f .collab/VERSION ]] || copy_file "$TEMPLATES/collab/VERSION" ".collab/VERSION"
  [[ -f .collab/ACTIVE.md ]] || copy_file "$TEMPLATES/collab/ACTIVE.md" ".collab/ACTIVE.md"
  [[ -f .collab/INDEX.md ]] || copy_file "$TEMPLATES/collab/INDEX.md" ".collab/INDEX.md"
  [[ -f .collab/ROUTING.md ]] || copy_file "$TEMPLATES/collab/ROUTING.md" ".collab/ROUTING.md"
  [[ -f .collab/PROTOCOL.md ]] || copy_file "$TEMPLATES/collab/PROTOCOL.md" ".collab/PROTOCOL.md"

  # For AI_AGENTS.md, refresh managed sections only.
  if [[ -f AI_AGENTS.md ]]; then
    refresh_managed_sections "AI_AGENTS.md" "$TEMPLATES/AI_AGENTS.md"
  else
    copy_file "$TEMPLATES/AI_AGENTS.md" "AI_AGENTS.md"
  fi

  # Sync descriptors (additive only — never remove user customizations).
  mkdir -p .collab/agents.d .collab/archive
  for yml in "$TEMPLATES/agents.d/"*.yml; do
    local name=$(basename "$yml")
    [[ -f ".collab/agents.d/$name" ]] || copy_file "$yml" ".collab/agents.d/$name"
  done
}

# refresh_managed_sections <target> <template>
# For every <!-- collab:NAME:start/end --> section in target, replace content
# with the content from template's same-named section.
refresh_managed_sections() {
  local target="$1"
  local template="$2"

  # Extract section names from template.
  local sections
  sections=$(grep -oE '<!-- collab:[a-z-]+:start -->' "$template" | sed -E 's/<!-- collab:([a-z-]+):start -->/\1/' | sort -u)

  for section in $sections; do
    if merge_has_section "$target" "$section" && merge_has_section "$template" "$section"; then
      # Extract template content between markers (exclusive).
      local new_content
      new_content=$(awk -v start="<!-- collab:${section}:start -->" -v end="<!-- collab:${section}:end -->" '
        $0 == start { in_sec = 1; next }
        $0 == end { in_sec = 0; next }
        in_sec { print }
      ' "$template")
      if [[ $DRY_RUN -eq 1 ]]; then
        say "would refresh section $section in $target"
      else
        merge_replace_section "$target" "$section" "$new_content"
      fi
    fi
  done
}

MODE=$(detect_mode)
say "Mode: $MODE"

case "$MODE" in
  fresh)
    setup_shared
    ;;
  re-init)
    re_init_shared
    ;;
  upgrade)
    echo "Upgrade from $(cat .collab/VERSION) to $(cat "$TEMPLATES/collab/VERSION") — see Task 17 (not yet shipped)."
    exit 1
    ;;
esac

# Agent selection.
if [[ ${#TARGET_AGENTS[@]} -eq 0 && -z "$ADD_AGENT" ]]; then
  for yml in ".collab/agents.d/"*.yml; do
    [[ -f "$yml" ]] || continue
    bootstrap_agent "$yml"
  done
elif [[ -n "$ADD_AGENT" ]]; then
  # --add-agent: only this one (Task 18 will add descriptor-creation wizard).
  bootstrap_agent ".collab/agents.d/${ADD_AGENT}.yml"
else
  for name in "${TARGET_AGENTS[@]}"; do
    bootstrap_agent ".collab/agents.d/${name}.yml"
  done
fi

if [[ $DRY_RUN -eq 0 ]]; then
  for f in AI_AGENTS.md .collab/ACTIVE.md .collab/INDEX.md .collab/ROUTING.md .collab/PROTOCOL.md; do
    [[ -f "$f" ]] && bash "$HERE/collab-register.sh" "$f" 2>/dev/null || true
  done
fi

say "Done. Repo at collab version $(cat .collab/VERSION 2>/dev/null || echo '?')."
```

**Step 2: Commit**

```bash
git add scripts/collab-init.sh
git commit -m "feat: add re-init mode to collab-init with marker-guided section refresh"
```

---

## Task 17: Upgrade mode (v1 is a no-op)

**Files:**
- Modify: `scripts/collab-init.sh`

For v0.1.0 there are no prior versions to upgrade from. This task replaces the `exit 1` stub with a clear "no migration path needed" message that still updates VERSION.

**Step 1: Modify the `upgrade)` case**

Replace:

```bash
  upgrade)
    echo "Upgrade from $(cat .collab/VERSION) to $(cat "$TEMPLATES/collab/VERSION") — see Task 17 (not yet shipped)."
    exit 1
    ;;
```

with:

```bash
  upgrade)
    local installed shipped
    installed=$(cat .collab/VERSION)
    shipped=$(cat "$TEMPLATES/collab/VERSION")
    say "Upgrading from $installed to $shipped"
    # v0.1.0 has no prior version, so no migration script. Future upgrades
    # will invoke scripts/migrations/<from>-to-<to>.sh if present.
    local migration="$HERE/migrations/${installed}-to-${shipped}.sh"
    if [[ -f "$migration" ]]; then
      say "Running migration: $migration"
      [[ $DRY_RUN -eq 1 ]] || bash "$migration"
    fi
    # After migration, run re-init to pick up any new template content.
    re_init_shared
    [[ $DRY_RUN -eq 1 ]] || echo "$shipped" > .collab/VERSION
    ;;
```

**Step 2: Commit**

```bash
git add scripts/collab-init.sh
git commit -m "feat: add upgrade mode to collab-init (no-op for v0.1.0, migration hook ready)"
```

---

## Task 18: `--add-agent`, `--dry-run`, `--force` flag semantics + legacy-merge prompt

**Files:**
- Modify: `scripts/collab-init.sh`

**Step 1: Flesh out `--add-agent` wizard behavior**

Replace the `--add-agent` branch of the agent-selection block with logic that requires the descriptor to already exist (user creates the YAML manually first; the command wires it in). Add a help hint.

Insert this function before the main dispatch block:

```bash
validate_descriptor_exists() {
  local name="$1"
  local path=".collab/agents.d/${name}.yml"
  if [[ ! -f "$path" ]]; then
    cat >&2 <<EOF
collab-init: descriptor for agent "$name" not found at $path

To add a new agent, first create the descriptor:
  cp templates/agents.d/claude.yml .collab/agents.d/$name.yml
  # then edit to set name/display/adapter_path/memory_dir/log_path

Then re-run:
  ./scripts/collab-init.sh --add-agent $name
EOF
    return 1
  fi
}
```

Update the `--add-agent` branch:

```bash
elif [[ -n "$ADD_AGENT" ]]; then
  validate_descriptor_exists "$ADD_AGENT"
  bootstrap_agent ".collab/agents.d/${ADD_AGENT}.yml"
```

**Step 2: Document `--dry-run` and `--force` in usage**

Expand `usage()` (already declared earlier) with notes — already covered.

**Step 3: `--force` behavior**

`$FORCE` is parsed but not yet used anywhere except reserving the flag. Wire `$FORCE` into `substitute_tokens` and `copy_file` so they overwrite existing files when set; without `--force`, existing files outside `.collab/` are preserved.

Update `copy_file`:

```bash
copy_file() {
  local src="$1"
  local dest="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "copy $src -> $dest"
    return 0
  fi
  if [[ -f "$dest" && $FORCE -eq 0 ]]; then
    say "skip (exists): $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}
```

Update `substitute_tokens` with the same guard before writing.

**Step 4: Commit**

```bash
git add scripts/collab-init.sh
git commit -m "feat: wire --add-agent validation, --force preservation guard, --dry-run previews"
```

---

## Task 19: Integration test — fresh bootstrap end-to-end

**Files:**
- Create: `tests/test-collab-init-fresh.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP"' EXIT

# Link scripts and templates into the tmp repo so collab-init finds them.
cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

(cd "$TMP" && bash scripts/collab-init.sh)

start_test "fresh bootstrap creates AI_AGENTS.md"
assert_file_exists "$TMP/AI_AGENTS.md"

start_test "fresh bootstrap creates .collab/ state files"
assert_file_exists "$TMP/.collab/VERSION"
assert_file_exists "$TMP/.collab/ACTIVE.md"
assert_file_exists "$TMP/.collab/INDEX.md"
assert_file_exists "$TMP/.collab/ROUTING.md"
assert_file_exists "$TMP/.collab/PROTOCOL.md"

start_test "fresh bootstrap creates descriptors"
assert_file_exists "$TMP/.collab/agents.d/claude.yml"
assert_file_exists "$TMP/.collab/agents.d/codex.yml"
assert_file_exists "$TMP/.collab/agents.d/gemini.yml"

start_test "fresh bootstrap creates Claude adapter + memory"
assert_file_exists "$TMP/.claude/CLAUDE.md"
assert_file_exists "$TMP/.claude/memory/state.md"
assert_file_exists "$TMP/.claude/memory/context.md"
assert_file_exists "$TMP/.claude/memory/decisions.md"
assert_file_exists "$TMP/.claude/memory/pitfalls.md"

start_test "fresh bootstrap creates Codex adapter + memory"
assert_file_exists "$TMP/.codex/CODEX.md"
assert_file_exists "$TMP/.codex/memory/state.md"

start_test "fresh bootstrap creates Gemini root adapter + memory"
assert_file_exists "$TMP/GEMINI.md"
assert_file_exists "$TMP/.gemini/memory/state.md"

start_test "fresh bootstrap creates work logs"
assert_file_exists "$TMP/docs/agents/claude.md"
assert_file_exists "$TMP/docs/agents/codex.md"
assert_file_exists "$TMP/docs/agents/gemini.md"

start_test "fresh bootstrap substitutes placeholder tokens"
# AGENT_DISPLAY should be substituted; no {{ remaining in claude's adapter.
if grep -qF "{{" "$TMP/.claude/CLAUDE.md"; then
  fail "unreplaced template tokens in .claude/CLAUDE.md"
else
  ok
fi

start_test "fresh bootstrap registers files in INDEX"
idx_lines=$(grep -c '^|' "$TMP/.collab/INDEX.md" || true)
# Expect: header + separator + >= 10 registered files.
[[ $idx_lines -ge 12 ]] && ok || fail "only $idx_lines INDEX rows; expected >= 12"

start_test "collab-check passes on a fresh bootstrap"
(cd "$TMP" && bash scripts/collab-check.sh) && ok || fail "collab-check reported mismatches"

report
```

**Step 2: Run**

```bash
chmod +x tests/test-collab-init-fresh.sh
bash tests/test-collab-init-fresh.sh
```

Expected: all assertions PASS.

**Step 3: Fix any regressions surfaced**

If the test fails, iterate on the relevant earlier task until green. Commit each fix separately with a descriptive message.

**Step 4: Commit the test**

```bash
git add tests/test-collab-init-fresh.sh
git commit -m "test: add end-to-end fresh bootstrap integration test"
```

---

## Task 20: Integration test — re-init preserves user content

**Files:**
- Create: `tests/test-collab-init-reinit.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP"' EXIT

cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

(cd "$TMP" && bash scripts/collab-init.sh)

# User customizes Claude adapter OUTSIDE managed markers.
cat >> "$TMP/.claude/CLAUDE.md" <<'EOF'

## User's custom section (outside markers)
This must survive re-init.
EOF

# User writes a new work-log entry.
cat >> "$TMP/docs/agents/claude.md" <<'EOF'

## 2026-04-22T12:00:00-05:00 — Custom entry
This entry should survive re-init.
EOF

# Re-run init in re-init mode.
(cd "$TMP" && bash scripts/collab-init.sh)

start_test "re-init preserves user content outside markers in adapter"
assert_file_contains "$TMP/.claude/CLAUDE.md" "User's custom section (outside markers)"

start_test "re-init preserves appended work-log entry"
assert_file_contains "$TMP/docs/agents/claude.md" "Custom entry"

start_test "re-init does not duplicate managed content"
count=$(grep -c '<!-- collab:behavioral-rules:start -->' "$TMP/AI_AGENTS.md" || true)
assert_eq "1" "$count"

start_test "re-init still passes collab-check"
(cd "$TMP" && bash scripts/collab-check.sh) && ok || fail "check failed after re-init"

report
```

**Step 2: Run**

```bash
chmod +x tests/test-collab-init-reinit.sh
bash tests/test-collab-init-reinit.sh
```

Expected: all PASS.

**Step 3: Commit**

```bash
git add tests/test-collab-init-reinit.sh
git commit -m "test: add re-init idempotency integration test preserving user content"
```

---

## Task 21: Integration test — `--add-agent` workflow

**Files:**
- Create: `tests/test-collab-init-add-agent.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/harness.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(make_tmp_repo)
trap 'rm -rf "$TMP"' EXIT

cp -R "$SKILL_ROOT/scripts" "$TMP/scripts"
cp -R "$SKILL_ROOT/templates" "$TMP/templates"

(cd "$TMP" && bash scripts/collab-init.sh)

start_test "--add-agent without descriptor errors cleanly"
out=$( (cd "$TMP" && bash scripts/collab-init.sh --add-agent cursor 2>&1) || true)
assert_contains "descriptor" "$out"

# Create the cursor descriptor manually (simulating the wizard steps).
cat > "$TMP/.collab/agents.d/cursor.yml" <<'EOF'
name: cursor
display: Cursor
adapter_path: .cursor/CURSOR.md
memory_dir: .cursor/memory
log_path: docs/agents/cursor.md
platform:
  config_discovery:
    - .cursor/CURSOR.md
  trigger_type: script-only
  bootstrap_command: "./scripts/collab-init.sh"
  supports_hooks: false
notes: |
  Test-only adapter for integration verification.
EOF

(cd "$TMP" && bash scripts/collab-init.sh --add-agent cursor)

start_test "--add-agent generates cursor adapter"
assert_file_exists "$TMP/.cursor/CURSOR.md"

start_test "--add-agent generates cursor memory"
assert_file_exists "$TMP/.cursor/memory/state.md"

start_test "--add-agent generates cursor work log"
assert_file_exists "$TMP/docs/agents/cursor.md"

start_test "--add-agent registers new files in INDEX"
assert_file_contains "$TMP/.collab/INDEX.md" ".cursor/CURSOR.md"

report
```

**Step 2: Run and commit**

```bash
chmod +x tests/test-collab-init-add-agent.sh
bash tests/test-collab-init-add-agent.sh
git add tests/test-collab-init-add-agent.sh
git commit -m "test: add --add-agent integration test for adapter elasticity"
```

---

## Task 22: Optional Claude pre-commit hook for Receipt enforcement

**Files:**
- Create: `templates/optional/claude-pre-commit-receipt.sh`
- Create: `docs/optional-hooks.md`

**Step 1: Write the hook script**

```bash
#!/usr/bin/env bash
# Optional pre-commit hook for Claude Code users.
# Asserts that any staged change to docs/agents/claude.md ends with a Task Receipt
# in the newest entry.
# Install via: cp templates/optional/claude-pre-commit-receipt.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
set -euo pipefail

LOG=docs/agents/claude.md

# Only enforce if the log is part of the staged changes.
if ! git diff --cached --name-only | grep -qx "$LOG"; then
  exit 0
fi

# Receipt regex: a `### Task Receipt` heading that is followed (within the next
# ~40 lines) by either a bullet starting with `-` or the phrase `Updates:`.
if awk '
  /^### Task Receipt/ { seen = 1; ctx = 40; next }
  seen && ctx-- > 0 {
    if (/^- / || /^Updates:/) { ok = 1; exit }
  }
  END { exit ok ? 0 : 1 }
' "$LOG"; then
  exit 0
fi

cat >&2 <<EOF
pre-commit: docs/agents/claude.md is being committed without a valid Task Receipt.

Add a '### Task Receipt' section to your latest entry listing which files this
task updated, OR use the trivial-task short form:

  ### Task Receipt
  Updates: none applicable (<short reason>)

See .collab/PROTOCOL.md for the full format.
EOF
exit 1
```

**Step 2: Write `docs/optional-hooks.md`**

```markdown
---
status: active
type: reference
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are setting up stronger enforcement for Claude-only repos"
skip-if: "you only use Codex or Gemini"
---

# Optional Enforcement Hooks

These are NOT installed by `collab-init.sh`. They ship as opt-in hardening for repos where agents have demonstrated Receipt drift.

## Claude pre-commit Receipt check

Location: `templates/optional/claude-pre-commit-receipt.sh`

Install:

```bash
cp templates/optional/claude-pre-commit-receipt.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Effect: blocks commits touching `docs/agents/claude.md` whose newest entry lacks a valid `### Task Receipt` section.

Disable: `rm .git/hooks/pre-commit` or `git commit --no-verify` (the latter only with explicit user approval).
```

**Step 3: Commit**

```bash
chmod +x templates/optional/claude-pre-commit-receipt.sh
git add templates/optional/ docs/optional-hooks.md
git commit -m "feat: add optional Claude pre-commit hook enforcing Task Receipt"
```

---

## Task 23: README update and CONTRIBUTING polish

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`

**Step 1: Update `README.md`**

Replace the "Installation" section with:

```markdown
## Installation

### In an empty or existing repo

```bash
git clone https://github.com/gpgaoplane/multi-agent-collab.git /tmp/multi-agent-collab
cd /path/to/your/repo
/tmp/multi-agent-collab/scripts/collab-init.sh
```

Or copy just `scripts/` and `templates/` into your repo and run `./scripts/collab-init.sh`.

### Re-running

Safe. `collab-init.sh` is idempotent. User content outside `<!-- collab:...:start/end -->` markers is preserved.

### Adding a new agent

```bash
cp templates/agents.d/claude.yml .collab/agents.d/newagent.yml
# edit fields
./scripts/collab-init.sh --add-agent newagent
```

### Flags

- `--agent <name>`    bootstrap a specific agent only
- `--add-agent <name>` bootstrap a new agent (descriptor must exist)
- `--dry-run`         preview without writing
- `--force`           overwrite non-marker content (destructive)

## Testing

```bash
./tests/run-all.sh
```

## Status

v0.1.0 — initial release. See `docs/design.md` for the full rationale.
```

**Step 2: Expand `CONTRIBUTING.md`** with a short section on how to add a new template/script (pointing at the TDD discipline in `docs/plans/2026-04-22-multi-agent-collab-implementation.md`).

**Step 3: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "docs: expand README with install/add-agent/test sections; polish CONTRIBUTING"
```

---

## Task 24: Tag v0.1.0 release

**Files:** none (git tag only)

**Step 1: Run full test suite**

```bash
./tests/run-all.sh
```

Expected: `ALL TEST FILES PASSED`.

**Step 2: Verify git status clean**

```bash
git status
```

Expected: clean tree, on `main`, ahead of origin/main by however many commits this plan produced.

**Step 3: Push to origin**

```bash
git push origin main
```

**Step 4: Tag and push the tag**

```bash
git tag -a v0.1.0 -m "v0.1.0 — initial release of multi-agent-collab skill"
git push origin v0.1.0
```

**Step 5: Verify the tag on GitHub**

Open https://github.com/gpgaoplane/multi-agent-collab/releases in a browser (or `gh release list`), confirm `v0.1.0` is visible.

---

## Completion checklist

- [ ] All 24 tasks committed.
- [ ] `./tests/run-all.sh` — PASS on all files.
- [ ] Fresh repo → `collab-init.sh` → structure matches `docs/design.md` §5.
- [ ] Existing repo with user content → `collab-init.sh` re-run → user content preserved.
- [ ] `--add-agent` extends existing repo without regressions.
- [ ] `v0.1.0` tag pushed to GitHub.
- [ ] README installation instructions verified working.

## After v0.1.0 ships

Next plan — apply skill to `graceful-wrap-up` as first real-world migration. Separate document: `docs/plans/2026-04-22-graceful-wrap-up-migration.md` (to be written in the `graceful-wrap-up` repo when you're ready).
