---
status: active
type: design-doc
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are designing, reviewing, or implementing the multi-agent-collab skill, or onboarding a new agent to the system"
skip-if: "you are only consuming the skill (bootstrapped repo) and not working on its internals"
related: [docs/plans/2026-04-22-multi-agent-collab-implementation.md]
---

# Multi-Agent Collab — Design Document

## 0. Context

This document designs a reusable skill, working title **`multi-agent-collab`**, that bootstraps a consistent multi-agent collaboration framework in any Git repository. The skill supports Claude Code, OpenAI Codex, and Google Antigravity / Gemini CLI as first-class agents, and is elastically extensible to additional agents (Cursor, Aider, Copilot CLI, custom) by dropping in a template.

The skill ships as:

- A standalone GitHub repository (reusable by other users) containing templates, a bootstrap script, and per-agent adapter files.
- A slash command (`/collab-init`) for Claude Code and a portable shell script (`scripts/collab-init.sh`) for all other agents.

The skill is **documentation-and-rules only** — no active enforcement beyond what each platform natively supports. Universality across agents is the design constraint that forces this.

After the skill is built and published, it will be applied to this repository (`graceful-wrap-up`) in a migration pass that absorbs the existing `AI_AGENTS.md`, `.claude/`, `.codex/`, and `docs/agents/` structure into the skill's canonical form with no context loss.

## 1. Problem statement

Multi-agent software repositories face five recurring failure modes:

1. **Context drift** — each agent develops an isolated view of the project; cross-agent knowledge is lost at session boundaries.
2. **Update incompleteness** — a task that touches multiple concerns (design, decision, implementation, state) often updates only one or two relevant files; others silently fall out of date.
3. **Unpredictable behavior** — without a shared rulebook, agents produce inconsistent commits, inconsistent documentation, and conflicting assumptions about ownership.
4. **File landfill** — documents proliferate without lifecycle, cluttering the repo and wasting context budget on irrelevant reads.
5. **Judgment paralysis** — when many memory/log files exist, agents spend effort deciding *where* to write rather than what to write; updates get misfiled or skipped.

The skill must directly address each.

## 2. Goals and non-goals

### Goals

- **G1 — Deterministic bootstrap.** Running `collab-init` in any repo produces the same canonical structure, idempotently.
- **G2 — Adapter elasticity.** Adding a new agent requires dropping a single template file, not a core rewrite.
- **G3 — No missing updates.** Every substantive task produces complete, fan-out updates across all relevant files, enforced by an end-of-task checklist + receipt.
- **G4 — No landfill.** Files have explicit lifecycle states; agents skip or archive stale content by convention.
- **G5 — No judgment paralysis.** A fan-out routing matrix tells agents exactly which files to update for each task dimension; section anchors tell them where inside the file.
- **G6 — Portable rules.** The rulebook works identically for Claude, Codex, and Gemini. No platform-specific enforcement required.
- **G7 — Token-efficient reads.** Agents skim frontmatter before body; skip files older than their watermark; use an INDEX as a single discovery point.
- **G8 — Migration safety.** Applying the skill to an existing repo merges additively without overwriting user content.

### Non-goals

- **NG1 — Active enforcement.** No pre-commit hooks, no hard gates beyond what an individual platform optionally enables. Rules are conventions.
- **NG2 — Quota or handoff tracking.** `AI_HANDOFF.md` / `RESUME_PROMPT.md` belong to the separate `graceful-wrap-up` system.
- **NG3 — File locking or concurrency primitives.** Branch-isolated work + the presence board are the only concurrency mechanisms. No leases, mutexes, or atomic-commit machinery.
- **NG4 — Dependency on a specific platform.** The skill must work when only one agent is used, when three are used in rotation, and when more are added later.

## 3. Glossary

| Term | Definition |
|---|---|
| **Agent** | An AI coding assistant operating in this repo (Claude, Codex, Gemini/Antigravity, or other). |
| **Session** | The lifetime of a running agent instance as identified by its platform session ID. Starts on agent startup; ends on agent exit. Automatic; no user ceremony. |
| **Task** | A logical unit of substantive work (code change, decision, design artifact, architecture change, investigation). Starts implicitly on a substantive user request; ends explicitly when the agent runs the End-of-Task Protocol. One session can contain zero or many tasks; one task can span multiple sessions. |
| **Substantive** | A task that hits at least one row of the fan-out matrix (rows 1–10 in §7). Casual conversation, lookups, and read-only exploration are not substantive and produce no receipt. |
| **Core five** | The five managed files every agent has: work log, state, context, decisions, pitfalls. |
| **Custom file** | Any other file an agent creates (design doc, investigation, migration plan). Permitted; must have frontmatter and INDEX registration. |
| **Fan-out** | The one-to-many relationship between a task and file updates. A typical substantive task triggers 3–6 updates. |
| **Receipt** | The required last section of each work-log entry summarizing which files the task updated. |
| **Adapter** | Platform-specific configuration file (`.claude/CLAUDE.md`, `.codex/CODEX.md`, `GEMINI.md`) that points its agent at the shared contract and adds only platform-specific notes. |
| **INDEX** | `.collab/INDEX.md`, the authoritative registry of every managed file with its status and last-updated timestamp. |
| **ACTIVE** | `.collab/ACTIVE.md`, the live presence board listing agents currently running in the repo. |
| **Watermark** | Per-agent `read-watermark` timestamp stored in `state.md`. Agents skip reading files older than their watermark on session start. |

## 4. Architecture overview

The framework is four thin layers:

1. **Shared contract layer** — `AI_AGENTS.md` (canonical rules, onboarding checklist, file map) + `.collab/` (INDEX, ACTIVE, reference docs).
2. **Per-agent adapter layer** — `.<agent>/` directory with a config entrypoint + four-file memory.
3. **Shared project-state layer** — `docs/STATUS.md` + `docs/agents/<agent>.md` per-agent outward-facing work log + `docs/plans/` for design/implementation artifacts.
4. **Tooling layer** — `scripts/` with bootstrap, timestamp helper, registration helper, and archive helper.

No file in any layer requires the others to exist. Each layer degrades gracefully if a peer is missing, because the skill is convention-based, not enforcement-based.

## 5. Directory and file layout

```
<repo-root>/
├── AI_AGENTS.md                       # canonical shared contract (marker sections)
├── GEMINI.md                          # Gemini/Antigravity pointer (platform requires root)
├── .collab/
│   ├── VERSION                        # skill version that initialized this repo
│   ├── ACTIVE.md                      # live presence board
│   ├── INDEX.md                       # authoritative file registry
│   ├── ROUTING.md                     # fan-out matrix reference
│   ├── PROTOCOL.md                    # End-of-Task Protocol reference
│   ├── agents.d/                      # per-agent descriptors (elasticity)
│   │   ├── claude.yml
│   │   ├── codex.yml
│   │   └── gemini.yml
│   └── archive/                       # archived managed files
├── .claude/
│   ├── CLAUDE.md                      # Claude adapter
│   └── memory/
│       ├── state.md
│       ├── context.md
│       ├── decisions.md
│       └── pitfalls.md
├── .codex/
│   ├── CODEX.md                       # Codex adapter
│   ├── SESSION_CHECKLIST.md
│   └── memory/ (same four files)
├── .gemini/
│   └── memory/ (same four files)      # adapter lives at root per Gemini convention
├── docs/
│   ├── STATUS.md                      # project-wide status (marker sections)
│   ├── agents/
│   │   ├── claude.md                  # outward-facing work log (append-only)
│   │   ├── codex.md
│   │   └── gemini.md
│   └── plans/                         # design + implementation artifacts
└── scripts/
    ├── collab-init.sh                 # bootstrap / re-init / add-agent
    ├── collab-now.sh                  # prints ISO-8601 timestamp
    ├── collab-register.sh             # adds a file to INDEX
    ├── collab-archive.sh              # moves a file to .collab/archive/
    └── collab-check.sh                # audits INDEX vs filesystem
```

File casing is lowercase throughout (`claude.md`, not `CLAUDE.md`) to avoid case-sensitivity surprises between Windows and Linux/macOS.

## 6. File schemas

### 6.1 Frontmatter

Every managed file — including `AI_AGENTS.md`, `docs/STATUS.md`, each core-five file, each custom file, each design doc — begins with YAML frontmatter:

```yaml
---
status: active              # active | stale | archived | reference-only
type: work-log              # work-log | state | context | decisions | pitfalls |
                            # design-doc | investigation | migration | adapter |
                            # shared | index | active-board | routing | protocol
owner: claude               # agent name OR "shared"
last-updated: 2026-04-22T10:15:30-05:00
read-if: "plain-language condition — why would someone read this now"
skip-if: "plain-language condition — when to stop at the frontmatter"
related: []                 # optional cross-references to sections or files
---
```

**Status values:**
- `active` — current, load-bearing, should be read when relevant.
- `stale` — was active, contents likely still true but no longer primary; skip on default scans. Recoverable by flipping back to `active` with a compaction pass.
- `archived` — historical; moved to `.collab/archive/`; ignored unless specifically requested.
- `reference-only` — durable reference not meant to be updated routinely (e.g., a design rationale document).

**Reading rule:** Read only the frontmatter first. If `status != active` or `read-if` doesn't match your need, stop. Cost: ~10 lines per file instead of hundreds.

### 6.2 Section anchors

Managed files are internally organized with HTML-comment markers so agents know *where inside the file* to write. Example for `state.md`:

```markdown
<!-- section:current-state:start -->
...
<!-- section:current-state:end -->

<!-- section:next-steps:start -->
...
<!-- section:next-steps:end -->

<!-- section:open-questions:start -->
...
<!-- section:open-questions:end -->

<!-- section:read-watermark:start -->
Last read INDEX at: 2026-04-22T10:15:30-05:00
<!-- section:read-watermark:end -->
```

Marker sections serve two purposes: (a) tell agents exactly where to write for each routing-card trigger, (b) enable idempotent re-init — `collab-init` updates only content between markers, leaving user content outside markers untouched.

### 6.3 INDEX

`.collab/INDEX.md` is the single discovery point. Format:

```markdown
---
status: active
type: index
owner: shared
last-updated: 2026-04-22T10:15:30-05:00
read-if: "session start, or before reading another agent's files"
skip-if: "never"
---

# File Registry

<!-- collab:index:start -->
| path | type | owner | status | last-updated |
|------|------|-------|--------|--------------|
| AI_AGENTS.md | shared | shared | active | 2026-04-22T00:00:00-05:00 |
| docs/agents/claude.md | work-log | claude | active | 2026-04-22T10:15:30-05:00 |
| docs/agents/codex.md | work-log | codex | active | 2026-04-22T09:00:00-05:00 |
| .claude/memory/state.md | state | claude | active | 2026-04-22T10:15:30-05:00 |
| .claude/memory/context.md | context | claude | active | 2026-04-22T00:00:00-05:00 |
| ... | | | | |
<!-- collab:index:end -->
```

**Invariants:**
- Every managed file is listed exactly once.
- Any file a session-start scan finds on disk but not in INDEX (or vice versa) triggers a reconcile prompt on the next agent's turn.
- Every write to a managed file updates its INDEX row's `last-updated` in the same turn.

### 6.4 ACTIVE

`.collab/ACTIVE.md` is the live presence board:

```markdown
---
status: active
type: active-board
owner: shared
last-updated: 2026-04-22T10:15:30-05:00
read-if: "session start, or you suspect another agent is running"
skip-if: "never"
---

# Active Agents

<!-- collab:active:start -->
| agent | session-id | branch | started-at |
|-------|------------|--------|------------|
| claude | 01HXYZ...  | codex/phase1-conversation-hooks | 2026-04-22T10:15:30-05:00 |
<!-- collab:active:end -->
```

**Behavior:**
- Agents add a row on session start (after running the bootstrap check).
- Agents remove their row on session end (SessionEnd hook for Claude; equivalent or script for others).
- Abrupt end → stale row survives. Next session detects the stale row, flags it, and first task becomes "reconcile prior session's state."
- Merge conflicts on `ACTIVE.md` are informational — they tell you two agents tried to write simultaneously. Resolution: take the union of rows.

### 6.5 The core five, per agent

Every agent has exactly five anchor files:

| File | Role | Write pattern | Typical contents |
|---|---|---|---|
| `docs/agents/<agent>.md` | Outward-facing work log | Append-only entries, each ending with a receipt | Dated entries with Changed / Why / Decisions / Watch out / Did not touch / Receipt |
| `.<agent>/memory/state.md` | Live session state | Overwrite sections | Current branch, active task, pause point, next steps, open questions, read-watermark |
| `.<agent>/memory/context.md` | Durable project truths | Append + periodic compaction | Invariants, architectural truths, non-obvious constraints |
| `.<agent>/memory/decisions.md` | Major design decisions | Append-only | Decision title, context, alternatives considered, choice, rationale, tradeoffs |
| `.<agent>/memory/pitfalls.md` | Recurring bugs / workarounds | Append-only | Symptom, root cause, workaround, test that catches regression |

These are *guaranteed slots* — every agent has exactly these, so cross-agent discovery is predictable. Agents may create additional files; they cannot omit any of these five.

### 6.6 Custom files

Agents may create any additional file they judge necessary (design notes, deep-dive investigations, migration plans, architecture overviews). Two non-negotiable obligations:

1. **Frontmatter** — as specified in §6.1.
2. **INDEX registration** — append one row to `.collab/INDEX.md` in the same turn the file is created.

An unregistered file is, by convention, invisible. No other agent is obligated to read it. This is the self-cleaning property: if you don't register, you don't exist; if you stop maintaining, you go `stale`; if still unused, `archived`.

## 7. Routing: fan-out matrix

The routing card is a **fan-out matrix**, not a single-match table. A task can trigger multiple rows; each row produces an independent update obligation.

| # | Dimension the task touched | Required update this turn |
|---|---|---|
| 1 | Wrote or changed code | `docs/agents/<you>.md` — new dated entry with receipt |
| 2 | Created a plan or design artifact | `docs/plans/YYYY-MM-DD-<topic>-{design,implementation}.md` + cross-link in `decisions.md` |
| 3 | Chose between alternatives | `.<agent>/memory/decisions.md` — append entry |
| 4 | Altered architecture or introduced an invariant | `.<agent>/memory/decisions.md` (decision) + `.<agent>/memory/context.md` (new invariant, if applicable) |
| 5 | Discovered a non-obvious durable truth | `.<agent>/memory/context.md` — append entry |
| 6 | Hit a recurring bug / gotcha / workaround | `.<agent>/memory/pitfalls.md` — append entry |
| 7 | Session state changed (branch, active task, pause, next step) | `.<agent>/memory/state.md` — overwrite affected sections |
| 8 | Tracked project task changed status | `docs/STATUS.md` — update managed section |
| 9 | Created any new document | Frontmatter added + `.collab/INDEX.md` — append row |
| 10 | Cross-agent risk to flag | `docs/agents/<you>.md` — explicit `Watch out:` block in the new entry |

**Core rule:** *Hit every row that applies, not the "most important" one. Over-update beats under-update. Stale is fixable; missing is silent data loss.*

`.collab/ROUTING.md` contains this matrix as the permanent reference so agents can re-read it without chasing the design doc.

## 8. End-of-Task Protocol and Receipt

The fan-out matrix produces obligations. The End-of-Task Protocol produces the **guarantee** that those obligations are met.

### 8.1 Protocol

Before declaring a task done — before the final agent response, before the commit — the agent walks the following checklist in its response. Each "yes" requires a corresponding update recorded in the Receipt.

```
## Task Completion Checklist

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
```

### 8.2 Receipt

The Receipt is a **required last section** of every work-log entry. Format:

```markdown
### Task Receipt
Updates fanned out this task:
- docs/agents/claude.md ........................... new entry 2026-04-22T10:15:30-05:00
- .claude/memory/decisions.md ..................... appended D-14 (OAuth fail-open)
- .claude/memory/context.md ....................... added "OAuth cascade rule"
- docs/STATUS.md .................................. Task 3 marked done
- .collab/INDEX.md ................................ timestamps refreshed
- docs/plans/2026-04-22-oauth-cascade-design.md ... new, frontmatter+registered

Missing / intentionally skipped: none
```

### 8.3 Trivial-task short form

If the task hit zero or one fan-out rows (read-only exploration, answering a clarification, running a lookup), the Receipt collapses to a single line:

```markdown
### Task Receipt
Updates: none applicable (read-only exploration)
```

The Protocol still runs — the short form is an assertion that the walk was performed and produced no required writes.

### 8.4 Soft enforcement

- **All platforms:** the work-log entry template in `AI_AGENTS.md` shows the Receipt section as required. Agents following the template produce it.
- **Claude only, optional:** a local hook can assert that the newest work-log entry ends with `### Task Receipt` before allowing a commit that touches `docs/agents/claude.md`. This is not shipped by default — it's offered as an optional hardening layer for repos where discipline is slipping.

## 9. Session model

Two tiers, decoupled.

### 9.1 Session (Tier 1 — automatic)

- **Identity:** platform session ID (Claude's `SESSION_ID`, Codex equivalent, Gemini equivalent). Opaque to the user.
- **Start:** SessionStart hook fires (Claude) / agent process begins / `collab-init` is run in a fresh shell. The agent:
  - Checks `.collab/VERSION` against the skill's installed version.
  - Adds a row to `.collab/ACTIVE.md`.
  - Reads `.collab/INDEX.md`.
  - Reads its own `state.md` to pick up `read-watermark`.
  - Reads other agents' files only if their INDEX `last-updated` > watermark.
  - Writes new watermark to `state.md`.
- **End:** SessionEnd hook fires / agent process exits / user closes CLI. Agent removes its `ACTIVE.md` row.
- **Purpose:** presence board, delta-read anchor. No documentation side effects by default.

### 9.2 Task (Tier 2 — explicit)

- **Start:** implicit — when the user issues a substantive request.
- **End:** explicit — agent completes the goal and runs the End-of-Task Protocol, OR user invokes an end-of-task command (platform-dependent; `/wrap-up` for Claude if the graceful-wrap-up skill is installed).
- **Cardinality:** one session contains ≥ 0 tasks; one task can span ≥ 1 sessions.
- **Purpose:** fan-out, receipts, work-log entries, STATUS updates.

### 9.3 Abrupt end recovery

If a session ends without proper teardown (crash, quota cutoff, window close with unsaved work):
- `ACTIVE.md` still contains the stale row.
- Next session's bootstrap sees the stale row, reads the owning agent's `state.md`, and surfaces a reconcile prompt: *"Prior session ended abruptly. Review uncommitted changes and finalize or archive prior task before starting new work."*
- The `graceful-wrap-up` system (in repos where it's installed) handles the *signal* side via StopFailure hooks; this skill defines the *convention* on top.

## 10. Delta-read mechanism

Each agent's `state.md` stores a `read-watermark`:

```markdown
<!-- section:read-watermark:start -->
Last read INDEX at: 2026-04-22T10:15:30-05:00
<!-- section:read-watermark:end -->
```

On session start, after reading its own files, an agent walks `.collab/INDEX.md`:

```
for row in INDEX:
  if row.owner == self: continue                          # own files already read
  if row.status != active: continue                       # skip stale/archived
  if row.last-updated <= read-watermark: continue         # not new since last session
  read row.path (frontmatter first; body only if read-if matches)

read-watermark = now
```

This bounds cross-agent reads to what has actually changed since last session. On a typical day-to-day resumption it may read zero or one file instead of everything.

## 11. Lifecycle and archival

Files have three states in regular use:

- **active** — load-bearing, read by default.
- **stale** — superseded or no longer primary; skip by default. Recoverable by compaction.
- **archived** — historical; physically moved to `.collab/archive/<original-path>`; removed from default reads.

### 11.1 Lifecycle rules

- **Creation:** files are born `active` with frontmatter + INDEX registration in the same turn.
- **Staling:** when an agent realizes a file is no longer load-bearing (e.g., a design doc whose content has migrated into `decisions.md`), they flip `status: stale` and update `last-updated`.
- **Archival:** an agent (or the End-of-Task sweep) may move `stale` files to `.collab/archive/` via `scripts/collab-archive.sh`. The INDEX row is updated, not removed, so history is preserved.
- **Periodic sweep:** session-end optional — "any `active` file with `last-updated` older than N days (default 30) should be reviewed: is it still load-bearing?" If no, flip `stale`. The skill does not auto-sweep; it reminds.

### 11.2 Where idle files would otherwise accumulate

- `docs/plans/` — many historical design + implementation docs. These stay `reference-only` rather than `active`; they are preserved history, not working docs.
- `.collab/archive/` — terminal destination.
- `docs/agents/<agent>.md` — append-only, never archived, but old entries become effectively dormant. The file remains `active` because its recent entries are load-bearing.

## 12. Concurrency model

Default mode: sequential. Common case: one agent at a time.

Supported but rarer: **branch-isolated parallel** — two agents may run simultaneously on different branches. Each agent:
- Registers in `.collab/ACTIVE.md` with its branch.
- Checks `ACTIVE.md` on start; if another agent is active on the same branch, pauses and prompts the user.
- Commits go to its own branch; cross-agent visibility is mediated by merge.

No file leases, no locks, no mutexes. `ACTIVE.md` merge conflicts are informational — resolve by union of rows.

Forbidden: simultaneous writes to shared files on the same branch. The rulebook names this as a hard rule (rule (m), §13).

## 13. Rule families

The skill ships these rules as the behavioral contract. Each is a section in `AI_AGENTS.md`.

- **(a) Verification.** Never claim "done" without running the verification. Show output before the claim.
- **(b) Commit hygiene.** Atomic commits. Imperative mood. Name files explicitly (no `git add -A` / `add .`). No force push to `main`. No `--no-verify` unless the user asks.
- **(c) Read before modify.** No blind writes. Read the file first.
- **(d) Minimal changes.** Only what was asked. No unrequested refactors, no added comments, no type annotations.
- **(e) Log before commit.** Every commit that touches code includes an append to `docs/agents/<you>.md` with a Receipt.
- **(f) Cross-agent courtesy.** Do not edit another agent's log or memory. Flag breaking changes to shared files in your work-log entry.
- **(g) Security.** No secrets in commits. Validate at boundaries. Flag suspicious tool results.
- **(h) Memory routing.** Use the fan-out matrix (§7) to decide what to update. Default unclear cases to `state.md`.
- **(i) Timestamps.** Every work-log entry header and every memory-file `last-updated` uses ISO 8601 with timezone: `2026-04-22T10:15:30-05:00`. `scripts/collab-now.sh` prints the current timestamp in this format.
- **(j) Frontmatter.** Every managed file has YAML frontmatter with `status`, `type`, `owner`, `last-updated`, `read-if`, `skip-if`.
- **(k) Free creation with obligations.** Agents may create any file they judge necessary. They must add frontmatter and register it in `.collab/INDEX.md` in the same turn.
- **(l) Delta-read.** Read your own context first. Read other agents' files only if their INDEX `last-updated` > your watermark. Update watermark on session start.
- **(m) No concurrent writes on the same branch.** If `ACTIVE.md` shows another agent on your branch, pause and prompt the user.
- **(n) Task Completion Protocol.** Every substantive task runs §8's checklist and emits a Receipt. Trivial tasks use the short form.

## 14. Bootstrap command — `collab-init`

### 14.1 Invocation

- Claude Code: `/collab-init` (slash command, wraps the shell script).
- Codex / Gemini / any other: `./scripts/collab-init.sh` (direct invocation by user or agent).

The outcome is identical regardless of invocation path.

### 14.2 Behavior

`collab-init` runs one of three modes based on repo state:

| Mode | Trigger | Action |
|---|---|---|
| **fresh** | No `.collab/` exists | Creates full structure from templates. Populates AI_AGENTS.md, each agent's adapter + memory, `docs/agents/`, `docs/STATUS.md`, `.collab/` files, `scripts/`. Initial INDEX populated from generated files. |
| **re-init** | `.collab/VERSION` exists and matches skill version | Idempotent verification. Re-emits any missing file. Updates content inside marker sections. Leaves content outside markers untouched. Reports diff. |
| **upgrade** | `.collab/VERSION` older than skill version | Runs the migration script for that version gap. Logs changes. Updates `VERSION`. |

### 14.3 Agent selection

By default, `collab-init` reads `.collab/agents.d/` and bootstraps every descriptor found. Each descriptor (`claude.yml`, `codex.yml`, `gemini.yml`) declares:

```yaml
# .collab/agents.d/claude.yml
name: claude
display: Claude
adapter_path: .claude/CLAUDE.md
memory_dir: .claude/memory
log_path: docs/agents/claude.md
platform:
  config_discovery: [.claude/CLAUDE.md, ~/.claude/CLAUDE.md]
  trigger_type: session-hook-or-slash-command
  bootstrap_command: "/collab-init"
  supports_hooks: true
```

Flags:
- `--agent <name>` — bootstrap only the named agent.
- `--add-agent <name>` — add a new agent descriptor and bootstrap only its files.
- `--dry-run` — show what would change.
- `--force` — overwrite non-marker content with template (destructive; warn loudly).

### 14.4 Marker-guided merge

For shared files that may already exist (`AI_AGENTS.md`, `docs/STATUS.md`), `collab-init`:
1. Reads the file.
2. Locates `<!-- collab:SECTION:start -->` and `<!-- collab:SECTION:end -->` pairs.
3. Replaces content between markers with the template's current content.
4. Leaves everything outside markers untouched.
5. If markers are absent (legacy file), prompts: "Insert managed sections here? [y/n/diff]".

This is the safe-merge pattern used by ESLint init, pre-commit, and Prettier. It lets users customize the file around the managed blocks without losing their changes on re-init.

## 15. Adapter elasticity

Adding a new agent (say `cursor`) requires three drops and one run:

1. Create `.collab/agents.d/cursor.yml` with the adapter descriptor.
2. Create a template in the skill repo: `templates/agents/cursor/ADAPTER.md` (or reuse the generic template).
3. Run `./scripts/collab-init.sh --add-agent cursor`.

`collab-init` then:
- Generates `.cursor/CURSOR.md` (or whatever the descriptor says).
- Generates `.cursor/memory/{state,context,decisions,pitfalls}.md` from the generic memory template.
- Generates `docs/agents/cursor.md` with the work-log header.
- Appends a row to `AI_AGENTS.md`'s managed "Current adapters" section.
- Registers all new files in INDEX.

No core code changes; just a descriptor + template. That is the elasticity.

## 16. Per-platform adapters

### 16.1 Claude

- **Entrypoint:** `.claude/CLAUDE.md` (project-scoped). Global `~/.claude/CLAUDE.md` continues to own universal preferences; the project file pointers at `AI_AGENTS.md` and references this project's in-repo memory.
- **Memory separation:**
  - `~/.claude/memory/` — universal personal preferences only. Untouched by the skill.
  - `.claude/memory/` — this project's truths (the core five minus the work log). Committed to git. Survives machine changes.
  - Rule in `.claude/CLAUDE.md`: "Global memory is for *you across all projects*. In-repo memory is for *this project across all Claudes*."
- **Hooks (optional):** SessionStart hook to run the bootstrap check; a pre-commit hook to assert Receipt presence on `docs/agents/claude.md` edits. Both are shipped as optional add-ons, not required.
- **Bootstrap invocation:** `/collab-init` slash command, backed by `scripts/collab-init.sh`.

### 16.2 Codex

- **Entrypoint:** `.codex/CODEX.md` (this repo's existing convention) + optional `AGENTS.md` pointer at root if the Codex version in use discovers `AGENTS.md`.
- **Session checklist:** `.codex/SESSION_CHECKLIST.md` continues to exist as a short reminder. Updated to reference the fan-out matrix and Receipt.
- **Memory:** `.codex/memory/{state,context,decisions,pitfalls}.md`. This repo already has exactly this structure; the skill canonicalizes it.
- **Bootstrap invocation:** `./scripts/collab-init.sh` (no slash-command equivalent). User or agent runs on start if the version check flags an upgrade.

### 16.3 Gemini / Antigravity

- **Entrypoint:** `GEMINI.md` at repo root (Gemini CLI's auto-discovery convention; cannot be moved into `.gemini/`).
- **Memory:** `.gemini/memory/{state,context,decisions,pitfalls}.md`. Memory files live under `.gemini/` even though the entrypoint is at root, because the root is already crowded.
- **Bootstrap invocation:** `./scripts/collab-init.sh`.
- **Notes:** Gemini's extension model is weaker than Claude's; no hook-level enforcement. Rules-only works fine because the framework is rules-only by design.

## 17. Existing-repo merge behavior

When `collab-init` runs in a repo that already has `AI_AGENTS.md`, `.claude/CLAUDE.md`, `.codex/CODEX.md`, or `docs/agents/`:

1. **Detect:** look for an existing `.collab/VERSION`.
2. **If absent:** treat as legacy migration. Walk each file that the skill manages and:
   - If the file has no markers: read it, display a diff of what `collab-init` would insert, prompt the user per section. Default answer is to wrap existing content as an unmanaged block and add fresh marker sections around it.
   - If the file has markers: treat as a re-init.
3. **If present, same version:** re-init (idempotent).
4. **If present, older version:** upgrade.

**Non-destructive guarantee:** no existing content is overwritten without an explicit user confirmation. The worst case on an unattended run is that the skill refuses to proceed and emits a diff report.

## 18. Migration plan for this repo (`graceful-wrap-up`)

Applying the skill to this repo is a one-time migration. Planned sequence:

### 18.1 Inventory

Current files → target state mapping:

| Current | Target | Action |
|---|---|---|
| `AI_AGENTS.md` | `AI_AGENTS.md` | Wrap current content in `<!-- collab:legacy:start/end -->`. Add managed marker sections for Rules, Routing, Onboarding. |
| `.claude/CLAUDE.md` | `.claude/CLAUDE.md` | Add frontmatter. Add managed sections. Preserve current pointers. |
| `.codex/CODEX.md` | `.codex/CODEX.md` | Add frontmatter. Add managed sections. Preserve existing memory routing rules (they match the skill's design). |
| `.codex/SESSION_CHECKLIST.md` | Same path | Add frontmatter. Add link to `.collab/PROTOCOL.md`. |
| `.codex/memory/session_state.md` | `.codex/memory/state.md` | Rename. Add frontmatter. Add section anchors. Preserve content. |
| `.codex/memory/project_context.md` | `.codex/memory/context.md` | Rename. Add frontmatter. |
| `.codex/memory/decision_log.md` | `.codex/memory/decisions.md` | Rename. Add frontmatter. |
| `.codex/memory/failure_patterns.md` | `.codex/memory/pitfalls.md` | Rename. Add frontmatter. |
| `docs/agents/claude.md` | Same path | Add frontmatter. Preserve all entries. New entries include Receipt. |
| `docs/agents/codex.md` | Same path | Same. |
| `docs/agents/antigravity.md` | `docs/agents/gemini.md` | Rename to match descriptor name. Add frontmatter. |
| `docs/STATUS.md` | Same path | Add marker sections (`current-phase`, `done`, `in-progress`, `up-next`, `test-results`, `branch`). |
| `~/.claude/memory/...` | Unchanged | Skill does not touch global memory. |
| `docs/plans/2026-04-2?-*.md` | Same paths | Add frontmatter as `reference-only`. Register in INDEX. |

### 18.2 New files created

- `.collab/VERSION`
- `.collab/ACTIVE.md`
- `.collab/INDEX.md` (populated by walking existing + new files)
- `.collab/ROUTING.md`
- `.collab/PROTOCOL.md`
- `.collab/agents.d/{claude,codex,gemini}.yml`
- `GEMINI.md` (root)
- `.gemini/memory/{state,context,decisions,pitfalls}.md`
- `scripts/collab-init.sh`, `collab-now.sh`, `collab-register.sh`, `collab-archive.sh`, `collab-check.sh`

### 18.3 Existing content preserved verbatim

- All current work-log entries in `docs/agents/claude.md` and `docs/agents/codex.md`.
- The `graceful-wrap-up` hook system (`src/hooks/`, `src/skills/`, `src/commands/`, `install.sh`, `uninstall.sh`, `tests/`).
- Historical design and implementation docs in `docs/plans/`.
- `AI_HANDOFF.md` and `RESUME_PROMPT.md` (runtime artifacts, owned by `graceful-wrap-up`).

### 18.4 Cutover commit sequence

1. Commit skill template files into a new branch `feat/multi-agent-collab`.
2. Commit `scripts/` and `.collab/` scaffolding.
3. Commit per-agent adapter updates with frontmatter and marker sections.
4. Commit memory-file renames (four renames for Codex).
5. Commit the initial INDEX.
6. Commit a migration note as the first receipt-bearing work-log entry in Claude's and Codex's logs.

One task → several commits, each atomic, but all part of the same migration task. The migration task itself produces one Receipt.

## 19. What we deliberately don't build

- **No file locking.** `ACTIVE.md` is informational. Concurrency safety = branches.
- **No auto-GC of stale files.** Agents declare stale; agents archive. No scheduled sweeper.
- **No cross-repo memory sync.** Each repo is an island.
- **No agent-to-agent messaging.** All cross-agent communication is file-based.
- **No enforcement of fan-out beyond rule language and (optional) Claude hook.** If an agent skips a row, nothing stops them at the platform level. Detection is via code review, cross-validation, or `scripts/collab-check.sh`.
- **No platform-specific feature reliance.** The skill must work when only Codex or only Gemini is in use.
- **No AI_HANDOFF.md / RESUME_PROMPT.md / quota logic.** Those belong to `graceful-wrap-up`.

## 20. Tradeoffs and open questions

### 20.1 Accepted tradeoffs

- **Receipt ceremony** — adds ~30 seconds per substantive task. Acceptable; that's the cost of completeness guarantee.
- **INDEX maintenance** — another file to keep current. Mitigated by the rule that every file creation/archival touches INDEX in the same turn, and by `scripts/collab-check.sh` auditing periodically.
- **Rule-based enforcement** — agents can technically skip rows and lie in the Receipt. True. The mitigation is culture + periodic review + Claude-specific optional hooks.
- **Frontmatter on every file** — adds 7–10 lines per file. Worth it because it makes every file self-describing and skippable.

### 20.2 Questions that don't block the design but need answers during implementation

- **INDEX format** — start with a markdown table. Consider TSV or JSON if parsing speed becomes a problem. Low priority; markdown is fine for <200 files.
- **Staling threshold** — default to 30 days in the rulebook. Repos with faster churn can override.
- **Periodic sweep automation** — the skill reminds; it doesn't enforce. Some users may want a pre-push hook that runs `collab-check.sh`. Offer as optional.
- **Upgrade migration script format** — version-to-version migrations will be shipped as `scripts/migrations/<from>-to-<to>.sh`. Simple shell scripts, not a migration framework.
- **Multi-repo / monorepo handling** — current scope is per-repo. Monorepo with multiple collaboration scopes (e.g., two teams in subdirectories) is out of scope for v1.

## 21. Summary

The `multi-agent-collab` skill is a rule-and-template framework that makes multi-agent repository work predictable, complete, and discoverable. Its central mechanisms are:

- A **shared contract** (`AI_AGENTS.md`) + **per-agent adapters** (elastic via descriptors).
- A **core-five memory model** per agent, plus **free custom files** with frontmatter + INDEX obligations.
- A **fan-out routing matrix** that maps task dimensions to required file updates.
- An **End-of-Task Protocol with Receipt** that makes update completeness visible and non-negotiable.
- A **two-tier session/task model** that uses automatic session boundaries for presence and explicit task boundaries for documentation.
- A **delta-read mechanism** powered by INDEX timestamps + per-agent watermarks, minimizing wasted cross-agent reads.
- A **marker-guided merge** in shared files, enabling idempotent bootstrap without overwriting user content.

Everything is convention and documentation. Nothing requires platform enforcement, which is what lets the same system apply to Claude, Codex, Gemini, and any future agent added by dropping a descriptor.

After this design is approved, the next document — `docs/plans/2026-04-22-multi-agent-collab-implementation.md` — will break it into sequential implementation tasks with verification steps, produced via the `writing-plans` skill.
