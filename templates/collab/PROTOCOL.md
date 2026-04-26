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

## Before committing

Commit only when the user explicitly asks, or at a clean task boundary with the user's standing approval. When in doubt, ask. Target: one commit per task — never per-edit. See `AI_AGENTS.md` `behavioral-rules > Commits > Cadence`.

## Trivial-task short form

If the task hit 0 or 1 fan-out rows (read-only exploration, clarification, lookup):

```markdown
### Task Receipt
Updates: none applicable (<short reason>)
```

The Protocol still runs — the short form is an assertion that the walk was performed and produced no required writes.

## Handoff rituals

When you finish a substantive chunk of work and another agent should validate, extend, or take over:

```bash
./scripts/collab-handoff.sh <to-agent> --from <your-name> --message "..." --files "a b c"
```

This writes a handoff block to your work log, drops your row from `.collab/ACTIVE.md`, and bumps the INDEX so receivers see the delta. Chain across agents with `--parent-id <previous-id>`.

At session start, run:

```bash
./scripts/collab-catchup.sh preview --agent <your-name> --handoff
```

to surface any open handoff targeting you. When you finish validating, close it:

```bash
./scripts/collab-handoff.sh close <id> --from <your-name>
```

## User vocabulary (universal across agents)

These phrases are a contract between the user and any agent — Claude / Codex / Gemini / others all respond identically.

**To trigger a handoff (sender side):**
- "wrap up for handoff [to <agent>]"
- "prepare handoff to <agent>"
- "hand it off to <agent>"
- "tag out to <agent>"

Agent action: run the End-of-Task Protocol → emit Receipt → run `./scripts/collab-handoff.sh <to-agent> --from <self> --message "…" --files "…"` → confirm with the printed handoff ID.

**To take a handoff (receiver side):**
- "take the baton"
- "pick up handoff [from <agent>]"
- "take over from <agent>"
- "you're up"

Agent action: run `./scripts/collab-catchup.sh preview --agent <self> --handoff`. If exactly one open block targets you, run `./scripts/collab-handoff.sh pickup <id> --from <self>` to print the summary and stamp `picked-up:` on the block. If multiple, ask the user which to pick up. After validation, close with `./scripts/collab-handoff.sh close <id> --from <self>`.

**Group handoffs.** Use `to: any` to target any available agent — `./scripts/collab-handoff.sh any --from <self>` writes a block visible to every agent's `--handoff` preview. The first agent to acknowledge owns it.

See `docs/handoff-schema.md` for the full block format and state machine.
