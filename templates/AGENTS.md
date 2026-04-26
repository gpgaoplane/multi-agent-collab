<!-- collab:agents-md:start -->
# Multi-Agent Collaboration

This repo uses the [`multi-agent-collab`](https://github.com/gpgaoplane/multi-agent-collab) skill for coordinating multiple AI coding agents (Claude, Codex, Gemini, and others). Every AI agent working here MUST read these files before taking any action:

1. **`AI_AGENTS.md`** — Shared contract: behavioral rules, onboarding checklist, fan-out routing.
2. **`.collab/INDEX.md`** — File registry. Use delta-read based on `last-updated` timestamps.
3. **`.collab/ROUTING.md`** and **`.collab/PROTOCOL.md`** — End-of-task fan-out matrix and Task Receipt format.
4. **Your own adapter** at `.<agent>/` (or `GEMINI.md` at root for Gemini).

## New-agent self-check (MANDATORY before first action)

If `.collab/agents.d/<your-agent-name>.yml` does NOT exist:

1. **Stop.** Do not proceed with any other work.
2. Ask the user to confirm your agent name (e.g., `opencode`, `cline`, `aider`).
3. Run: `./scripts/collab-init.sh --join <your-agent-name>`
4. That command creates your adapter, memory dir, work log, and descriptor, and registers them in `.collab/INDEX.md`.
5. Then proceed with the Onboarding Checklist in `AI_AGENTS.md`.

Skipping this step means you will step on other agents' files without logging your work. Do not skip.
<!-- collab:agents-md:end -->

<!-- collab:critical-rules:start -->
## Critical rules (read these even if you only have AGENTS.md loaded)

- **Receipt is required.** Every substantive task ends with a Task Receipt in your work log (`docs/agents/<self>.md`). See `.collab/PROTOCOL.md`.
- **Read before modify.** Read a file's frontmatter before editing it. No blind writes.
- **Commit cadence.** Commit only when the user asks, or at a clean task boundary with standing approval. One commit per task — never per-edit.
- **Post-compact:** if your context just compacted, re-read `AI_AGENTS.md` behavioral-rules and your own `state.md` before the next substantive write.

Full rules + onboarding checklist live in `AI_AGENTS.md`.
<!-- collab:critical-rules:end -->
