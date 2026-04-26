---
name: multi-agent-collab
description: Bootstrap multi-agent AI collaboration structure (shared contract, per-agent adapters, memory, work logs, fan-out routing, end-of-task Protocol) in any git repo. Invoke only when the user explicitly asks to set up multi-agent collaboration, add a new agent to an existing collab-enabled repo, or check whether the structure is already installed.
license: MIT
version: 0.4.1
---

# multi-agent-collab — bootstrap

## Step 1: Check current state (MANDATORY — do this before anything else)

Run in the user's current repo:

```bash
test -f .collab/VERSION && cat .collab/VERSION || echo "not installed"
```

**If the output is a version string (e.g., `0.2.0`):**
The repo is already bootstrapped. STOP. Tell the user:
"multi-agent-collab is already installed (version X.Y.Z)."
Do NOT re-run bootstrap. Only continue to Step 3 if the user has
explicitly asked to add another agent.

**If the output is `not installed`:**
Proceed to Step 2.

## Step 2: Fresh bootstrap

Preferred invocation (works from any agent, no clone required):

```bash
npx @gpgaoplane/multi-agent-collab init
```

Fallback (if `npx` is unavailable, or the skill is installed as a
local clone at `$SKILL_DIR`):

```bash
bash "$SKILL_DIR/scripts/collab-init.sh"
```

**Calling-agent-only install (v0.4.0+).** `init` bootstraps **only the
agent that ran it**. Detection precedence:

1. `--agent <name>` flag (explicit override)
2. `$COLLAB_AGENT` env var
3. Env-var probe (`CLAUDECODE`, `CODEX_HOME`, `GEMINI_CLI`, …)
4. Hard-fail with guidance if nothing matches

Other agents arrive later via `join` (Step 3). Both paths are
idempotent. User content outside `<!-- collab:...:start/end -->`
markers is preserved on re-run.

After a claude-only bootstrap, the target repo contains:

- `AI_AGENTS.md` — shared contract (Current Adapters table is dynamic)
- `AGENTS.md` — cross-agent front door pointing at AI_AGENTS.md
- `.collab/` — INDEX, ACTIVE, ROUTING, PROTOCOL, calling agent's descriptor
- `.claude/` and `docs/agents/claude.md` — adapter, memory, work log
- (no `.codex/`, no `.gemini/`, no `GEMINI.md` until you `join` them)

## Step 3: Add a new agent (only when user explicitly requests)

Run in the target repo:

```bash
npx @gpgaoplane/multi-agent-collab join <agent-name>
```

Or with a local clone:

```bash
bash "$SKILL_DIR/scripts/collab-init.sh" --join <agent-name>
```

The `--join` flag performs a three-tier descriptor lookup:
1. Existing user descriptor at `.collab/agents.d/<name>.yml` — used as-is.
2. Known agent (claude / codex / gemini) — uses shipped descriptor.
3. Unknown — renders generic template with sensible defaults.

For unknown agents with non-standard conventions (e.g., adapter file
at repo root instead of `.{name}/`), the user should edit
`.collab/agents.d/<name>.yml` after generation, then re-run `--join`.

## What this skill does NOT do

- It does NOT install itself repeatedly. The state check in Step 1
  short-circuits on already-installed repos.
- It does NOT modify files outside the managed marker sections.
- It does NOT enforce rules. Runtime behavioral conventions live in
  `AI_AGENTS.md` (produced at bootstrap), read by every agent every
  session. This skill file is the installer only.

## Related files in this skill directory

- `docs/design.md` — full rationale and design philosophy
- `docs/plans/2026-04-22-multi-agent-collab-implementation.md` — v0.1.0 build plan
- `docs/plans/2026-04-22-v0.2.0-distribution.md` — v0.2.0 release plan
- `README.md` — end-user install and usage
