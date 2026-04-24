# multi-agent-collab

A reusable skill for bootstrapping consistent multi-agent collaboration in any Git repository. Supports Claude Code, OpenAI Codex, and Google Antigravity / Gemini CLI out of the box, and is elastically extensible to additional agents (OpenCode, Cline, Aider, Cursor, Copilot CLI, custom) via the `--join` flow.

## Status

v0.3.0 — cross-agent handoff and enforcement. See [`docs/design.md`](docs/design.md) for the full rationale and [`CHANGELOG.md`](CHANGELOG.md) for release history.

## What's new in v0.3.0

- **Cross-agent handoff** — `collab-handoff <to-agent>` writes a structured handoff block with chain support (`A→B→C→A`).
- **Delta-read on demand** — `collab-catchup` previews files newer than your watermark; `ack` commits it (two-phase keeps it honest).
- **Presence board is writable** — `collab-presence start|end` manages `.collab/ACTIVE.md` rows. Handoff auto-removes the sender on completion. Full "load-bearing" adoption depends on per-agent session-start hooks (optional snippets shipped under `templates/optional/`).
- **Receipt enforcement** — opt-in portable pre-commit hook via `collab-init --install-hooks`. `.collab/config.yml: strict: true` turns warnings into blocks.
- **Update advisory** — `collab-check` reports when a newer npm version exists (silent in CI, cache 24h).
- **Session-start snippets** (optional) — per-agent hooks surface remote drift automatically.
- **Visible empty-state seeds** — empty memory files no longer look like broken installs.
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

The bootstrap detects the previous version and runs the migration chain automatically (v0.1.0 installs will run both `0.1.0-to-0.2.0.sh` and `0.2.0-to-0.3.0.sh`; v0.2.0 installs run only the latter). User content outside marker sections is preserved.

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
