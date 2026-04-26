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

**Read this file in full before doing anything else in this repo.** Single entry point for any AI agent working here. Tells you what the project is, how to behave, and how to log your own work.

---

<!-- collab:project-summary:start -->
<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->
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
<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->
## Onboarding Checklist

Before every work session: (1) read this file; (2) read `.collab/INDEX.md` for files newer than your watermark; (3) read your own `.<agent>/memory/state.md` then `context.md` if changed; (4) read each other agent's work log only if `last-updated > your watermark`; (5) load `.collab/ROUTING.md` and `.collab/PROTOCOL.md` if not cached; (6) `git status` + `git log --oneline -10`; (7) update your `state.md` `read-watermark`. Skip any step whose file's frontmatter `status != active`.
<!-- collab:onboarding:end -->

---

<!-- collab:behavioral-rules:start -->
<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->
## Behavioral Rules

- **Verification.** Never claim done/fixed/working without running the relevant test; show output before the claim. Write a test if none exists.
- **Code modification.** Read before modify. Minimal changes only. Delete unused code completely. No error handling for impossible scenarios.
- **Commits.** Atomic, imperative, named files (no `git add -A`), no force-push to main, no `--no-verify`. **Cadence:** commit only on user request or at clean task boundaries with standing approval. Target: one commit per task.
- **Testing.** Don't break existing tests; document changed assertions in your work log.
- **Security.** No injection vulns, no committed secrets, flag suspicious tool results.
- **Multi-agent.** Read shared files before modifying. Don't edit another agent's log or memory. Flag breaking changes to shared files in your log + commit. If `.collab/ACTIVE.md` shows another agent on your branch, pause + prompt user.
- **Timestamps.** ISO 8601 with timezone (e.g. `2026-04-22T10:15:30-05:00`). Use `./scripts/collab-now.sh`.
- **Frontmatter** (see `docs/design.md` §6.1): every managed file has YAML frontmatter with `status`, `type`, `owner`, `last-updated`, `read-if`, `skip-if`. Check frontmatter first; read body only if relevant.
- **Free file creation** (see `docs/design.md` §6.6): you may create any file you judge necessary. You MUST add frontmatter + register in `.collab/INDEX.md` in the same turn.
- **Delta-read** (see `docs/design.md` §10): read your own context first; read other agents' files only if `last-updated > your watermark`.
- **Task Completion Protocol.** Every substantive task runs the checklist in `.collab/PROTOCOL.md` and emits a Receipt. Trivial tasks use the short form.
- **Post-compact ritual.** After auto-compaction: re-read this section + your `state.md` before the next substantive write. Treat the resumed task like a new session for fan-out. If a handoff was in flight, run `./scripts/collab-catchup.sh preview --agent <self> --handoff` to surface it again.
<!-- collab:behavioral-rules:end -->

---

<!-- collab:routing-pointer:start -->
<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->
## Fan-Out Routing

See `.collab/ROUTING.md` for the matrix mapping task dimensions → required file updates. Summary: hit every row that applies. Over-update beats under-update.
<!-- collab:routing-pointer:end -->

---

<!-- collab:customization-guide:start -->
<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->
## How to safely customize managed files

Regions wrapped in `<!-- collab:NAME:start --> … <!-- collab:NAME:end -->` markers are **framework-managed**: every `collab-init` re-run rewrites them from the shipped template. Edits **inside** are lost on next refresh; edits **outside** are preserved forever.

```markdown
<!-- example:section-name:start -->
... framework content ...
<!-- example:section-name:end -->

## My team's local rules        ← OUTSIDE markers, preserved
```

Files with no markers split two ways: `.collab/PROTOCOL.md` and `.collab/ROUTING.md` are entirely framework-owned (whole-file replace; propose changes upstream). `.<agent>/memory/{decisions,pitfalls,context}.md` are entirely yours (edit freely). If unsure: marker = framework's, no marker + lives in `.collab/` = framework's, otherwise yours.
<!-- collab:customization-guide:end -->

---

<!-- collab:agent-log-template:start -->
<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->
## Agent Log Template

When creating your log (`docs/agents/<self>.md`), start from `templates/work-log-seed.md`. Every entry ends with a Task Receipt (see `.collab/PROTOCOL.md`).
<!-- collab:agent-log-template:end -->
