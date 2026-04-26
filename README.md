# multi-agent-collab

A reusable skill for bootstrapping consistent multi-agent collaboration in any Git repository. Supports Claude Code, OpenAI Codex, and Google Antigravity / Gemini CLI out of the box, and is elastically extensible to additional agents (OpenCode, Cline, Aider, Cursor, Copilot CLI, custom) via the `--join` flow.

## Status

v0.4.0 — calling-agent-only bootstrap, log rotation, vocabulary symmetry. See [`docs/design.md`](docs/design.md) for the full rationale, [`docs/plans/2026-04-25-v0.4.0-plan.md`](docs/plans/2026-04-25-v0.4.0-plan.md) for the release plan, and [`CHANGELOG.md`](CHANGELOG.md) for release history.

## What's new in v0.4.0

- **Calling-agent-only bootstrap** — `init` materializes only the agent that ran it. Detection probes env vars; falls back to `--agent <name>` or `$COLLAB_AGENT`; hard-fails with guidance when nothing matches. Other agents arrive via `join`.
- **Dynamic adapter table** — `Current Adapters` section in `AI_AGENTS.md` is rendered from `.collab/agents.d/` and re-rendered on every init/join/migration.
- **Work-log rotation** — `collab-rotate-log.sh <agent>` archives older entries (default: 300-line threshold, keep 8 entries) preserving Receipts as one-line summaries and open handoff blocks verbatim. CRLF + `## subsection` aware.
- **Handoff pickup verb + vocabulary** — `collab-handoff pickup <id> --from <self>` prints summary + stamps `picked-up:`. Sender phrases ("wrap up for handoff") and receiver phrases ("take the baton") documented in PROTOCOL.md. Group `to: any` handoffs supported.
- **Upgrade communication** — migrations emit `>>> Upgrade summary:` blocks; the upgrade chain writes `.collab/UPGRADE_NOTES.md` for the next agent to read. `collab-init --ack-upgrade` archives it. `collab-check` surfaces it at top of output.
- **Migration safety** — auto-backup on upgrade (`.collab/backup/...`), `--restore <id>`, `--diff` (preview migrations without applying), `--force-dirty` override for the new pre-migration cleanliness check. Loud BEFORE/AFTER per-file logging.
- **Marker warnings** — every framework-managed `<!-- collab:NAME:start -->` block now has an inline warning comment; `AI_AGENTS.md` ships a `collab:customization-guide` section explaining the edit-outside-markers convention.
- **Post-compact ritual** — explicit guidance in AI_AGENTS.md for what to re-read after auto-compaction. Optional Claude `PreCompact` hook template.
- **Commit cadence rule** — `Cadence` bullet under AI_AGENTS.md `Commits` formalizes the "commit only on user request or task boundaries" convention.
- **Critical rules inlined into AGENTS.md** — Receipt requirement, read-before-modify, commit cadence, post-compact pointer surfaced in the auto-discovered front-door file.
- **`AI_AGENTS.md` trimmed to ≤100 lines** — verbose explanations relocated to `docs/design.md` (already reference-only); load-bearing rules retained inline.
- **User vocabulary** — natural-language phrases for rotation ("rotate the log") and upgrade ("update the framework") map to commands.
- **`collab-register --type/--owner/--status` flags** — register files that lack frontmatter, or override frontmatter values.
- **`collab-check --stats`** — per-agent diagnostic table with entries, log lines, open handoffs, archive counts.
- **0.3.0 → 0.4.0 migration** — interactive prune of agents with seed-only work logs. Calling agent is never flagged.
- **~196 new tests.**

## What v0.3.0 shipped

- **Cross-agent handoff** — `collab-handoff <to-agent>` writes a structured handoff block with chain support (`A→B→C→A`).
- **Delta-read on demand** — `collab-catchup` previews files newer than your watermark; `ack` commits it (two-phase keeps it honest).
- **Presence board** — `collab-presence start|end` manages `.collab/ACTIVE.md` rows.
- **Receipt enforcement** — opt-in portable pre-commit hook via `collab-init --install-hooks`. `.collab/config.yml: strict: true` blocks instead of warning.
- **Update advisory** — `collab-check` reports when a newer npm version exists.
- **Session-start snippets** (optional) — surface remote drift automatically.
- **Auto-publish** — tag `v*` → GitHub Actions publishes to npm.

## What this skill does

- Bootstraps a canonical directory structure for multi-agent work: shared contract (`AI_AGENTS.md`), cross-agent front door (`AGENTS.md`), per-agent adapters (`.claude/`, `.codex/`, `.gemini/`, …), per-agent memory, outward-facing work logs.
- Ships a shared behavioral ruleset every agent inherits — verification, commit hygiene, read-before-modify, cross-agent courtesy, memory routing, timestamp conventions, delta-read.
- Defines a fan-out routing matrix and End-of-Task Protocol with required Receipts, so substantive tasks never leave relevant files un-updated.
- Uses YAML frontmatter + a central `.collab/INDEX.md` + per-agent read-watermarks so agents skip irrelevant files and read only what changed since their last session.
- Is idempotent on re-run and merge-safe for existing repos via marker-guided sections (`<!-- collab:SECTION:start/end -->`).

## Design summary

Five central mechanisms:

1. **Shared contract + per-agent adapters**, elastic via YAML descriptors in `.collab/agents.d/`.
2. **Core-five memory model** per agent (work log, state, context, decisions, pitfalls), plus free custom files with frontmatter + INDEX obligations.
3. **Fan-out routing matrix** mapping task dimensions to required file updates.
4. **End-of-Task Protocol + Receipt** making update completeness visible and non-negotiable.
5. **Two-tier session/task model** — automatic session boundaries for presence, explicit task boundaries for documentation.

## Installation

Three channels — pick whichever fits your setup. All three run the same bootstrap and produce the same result.

### Via npm (recommended)

```bash
npx @gpgaoplane/multi-agent-collab init
```

Runs without permanent install. For a permanent install:

```bash
npm install -g @gpgaoplane/multi-agent-collab
multi-agent-collab init
```

**Calling-agent-only install (v0.4.0+).** `init` bootstraps only the agent that runs it. Detection ladder:

1. `--agent <name>` flag wins.
2. `$COLLAB_AGENT` env var if no flag.
3. Probe of `CLAUDECODE`, `CLAUDE_CODE_SSE_PORT`, `CLAUDE_CODE_OAUTH_TOKEN`, `CODEX_HOME`, `CODEX_CLI`, `GEMINI_CLI`, `GEMINI_API_KEY`, `GOOGLE_AI_API_KEY`.
4. Hard-fail with re-run guidance if nothing matches.

To install with a specific agent regardless of detection:

```bash
npx @gpgaoplane/multi-agent-collab init -- --agent codex
# or:
COLLAB_AGENT=codex npx @gpgaoplane/multi-agent-collab init
```

### Via skill drop-in (for SKILL.md-aware agents)

Claude Code, OpenCode, Cursor, and several other agents auto-discover skills in `~/.claude/skills/` and `~/.agents/skills/`. Clone this repo there:

```bash
git clone https://github.com/gpgaoplane/multi-agent-collab.git ~/.claude/skills/multi-agent-collab
```

When the user asks the agent to "set up multi-agent collaboration," the agent loads `SKILL.md`, checks whether the target repo is already bootstrapped, and runs the installer if not. Updates: `git pull` inside that clone.

### Via direct clone (no npm, no agent)

```bash
git clone https://github.com/gpgaoplane/multi-agent-collab.git /tmp/multi-agent-collab
cd /path/to/your/repo
/tmp/multi-agent-collab/scripts/collab-init.sh
```

## Adding a new agent

```bash
# In a repo already bootstrapped with multi-agent-collab:
npx @gpgaoplane/multi-agent-collab join <agent-name>
```

`<agent-name>` can be any agent:

- **Known** (shipped descriptor): `claude`, `codex`, `gemini`.
- **Unknown** (generic descriptor auto-generated): `opencode`, `cline`, `aider`, `cursor`, `windsurf`, or anything else.

For agents with non-standard conventions (e.g., adapter file at repo root instead of `.{name}/`), edit the auto-generated descriptor at `.collab/agents.d/<name>.yml` then re-run `join`.

## Upgrading

```bash
npx @gpgaoplane/multi-agent-collab init
```

The bootstrap detects the previous version and runs the full migration chain (e.g. v0.1.0 → v0.4.0 runs `0.1.0-to-0.2.0.sh`, `0.2.0-to-0.3.0.sh`, `0.3.0-to-0.4.0.sh` in order). User content outside marker sections is preserved.

### Upgrading from v0.3.0 to v0.4.0 — step by step

In each repo bootstrapped at v0.3.0:

1. **Commit or stash any in-flight work.** v0.4.0 runs a cleanliness check at the start of upgrades and refuses to proceed on a dirty working tree (override with `--force-dirty` if you really want to mix the diffs).
2. **(Optional) Preview the migration without applying it:**
   ```bash
   npx @gpgaoplane/multi-agent-collab init -- --diff
   ```
   Prints unified-diff hunks per changed file, then restores the repo to its pre-migration state. Doesn't keep any UPGRADE_NOTES.md or backup directory behind.
3. **Run the upgrade:**
   ```bash
   npx @gpgaoplane/multi-agent-collab init
   ```
   - **Auto-backup** runs first: snapshots all framework-managed files into `.collab/backup/0.3.0-to-0.4.0-<timestamp>/`. Disable with `--no-backup` if you don't want it.
   - **Migration prompts** appear if the 0.3.0→0.4.0 migration detects agents with seed-only work logs (no real entries). Per-agent yes/no, default *keep*. The calling agent is never flagged. Non-interactive contexts (CI, no tty, `COLLAB_MIGRATE_NONINTERACTIVE=1`) skip the prompts and keep everything. To prune all flagged seed-only agents non-interactively (destructive, intentional), set `COLLAB_MIGRATE_REMOVE_ALL_SEED=1`.
   - **`>>> Upgrade summary:`** blocks print to stdout listing what each migration changed.
   - **`.collab/UPGRADE_NOTES.md`** is written. Status `transient` — the next agent to start a session reads it, follows the post-upgrade ritual, then runs `collab-init --ack-upgrade` to archive it.
4. **Rollback if anything looks wrong:**
   ```bash
   bash scripts/collab-init.sh --restore latest
   ```
   Or `--restore <specific-backup-id>` to pick a particular backup directory.

### Natural-language phrases agents understand (v0.4.0+)

You can speak any of these to a Claude/Codex/Gemini session in a bootstrapped repo and the agent runs the right command:

- **Upgrade:** "update the framework", "get the latest version", "is there a new version" (check-only), "update multi-agent-collab".
- **Rotation:** "rotate the log", "trim my work log", "compact the work log", "archive old entries", "the log is getting long".
- **Handoff (sender):** "wrap up for handoff", "prepare handoff to <agent>", "tag out to <agent>".
- **Handoff (receiver):** "take the baton", "pick up handoff", "take over from <agent>", "you're up".

Full vocabulary contract in `templates/collab/PROTOCOL.md`.

## Flags (all channels)

- `init` — bootstrap the current repo (fresh, re-init, or upgrade; auto-detected)
- `join <name>` — add an agent with three-tier descriptor lookup
- `check` — audit INDEX vs filesystem
- `archive <path>` — move a file to `.collab/archive/` and flip its status
- `register <path>` — register a file in INDEX (used internally, exposed for custom flows)

Underlying bash script accepts also:

- `--agent <name>` (repeatable) — bootstrap a specific agent only
- `--add-agent <name>` — add an agent whose descriptor already exists (v0.1.0-compatible)
- `--dry-run` — preview without writing
- `--force` — overwrite non-marker content (destructive)

### Cross-agent workflow commands

- `handoff <to-agent> --from <name> [--message ...] [--files ...]` — sender writes a handoff block
- `handoff close <id> --from <name>` — receiver marks block done
- `catchup preview --agent <name> [--handoff]` — see what changed, or surface open handoffs
- `catchup ack --agent <name>` — commit current time as INDEX watermark
- `presence start|end --agent <name>` — manage ACTIVE.md presence rows

## Requirements

- `git`, `bash`
- For npm channel: Node.js ≥18
- On Windows: Git for Windows (includes Git Bash)

## Testing

```bash
./tests/run-all.sh
```

All tests must pass before merge. TDD is required for new scripts.

## License

MIT. See [`LICENSE`](LICENSE).
