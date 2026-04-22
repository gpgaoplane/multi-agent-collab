# multi-agent-collab

A reusable skill for bootstrapping consistent multi-agent collaboration in any Git repository. Supports Claude Code, OpenAI Codex, and Google Antigravity / Gemini CLI out of the box, and is elastically extensible to additional agents (Cursor, Aider, Copilot CLI, custom) by dropping in a descriptor.

## Status

**In design.** The implementation plan and skill itself are not yet built. See [`docs/design.md`](docs/design.md) for the full design document.

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

Not yet implemented. Design phase only.

## License

TBD.
