# multi-agent-collab

A reusable skill for bootstrapping consistent multi-agent collaboration in any Git repository. Supports Claude Code, OpenAI Codex, and Google Antigravity / Gemini CLI out of the box, and is elastically extensible to additional agents (Cursor, Aider, Copilot CLI, custom) by dropping in a descriptor.

## Status

v0.1.0 — initial release. See [`docs/design.md`](docs/design.md) for the full rationale.

## What this skill does

- Bootstraps a canonical directory structure for multi-agent work: shared contract (`AI_AGENTS.md`), per-agent adapters (`.claude/`, `.codex/`, `.gemini/`), per-agent memory, outward-facing work logs.
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

- `--agent <name>`     bootstrap a specific agent only
- `--add-agent <name>` bootstrap a new agent (descriptor must exist)
- `--dry-run`          preview without writing
- `--force`            overwrite non-marker content (destructive)

## Testing

```bash
./tests/run-all.sh
```

## License

MIT. See [`LICENSE`](LICENSE).
