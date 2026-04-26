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

## Log rotation vocabulary (universal)

When a work log grows past the threshold (default 300 lines), the user will not always remember the exact command. These phrases are a contract: any agent hearing them runs the rotation command.

**User says** (any of):
- "the log is getting long, let's compact it"
- "rotate the log" / "rotate my log"
- "summarize old entries"
- "trim my work log" / "trim the log"
- "archive old entries"
- "this log is getting heavy, clean it up"
- "compact the work log"

**Agent action:** run `./scripts/collab-rotate-log.sh <self>` (use your own agent name). Confirm with the printed summary line. If `collab-check` previously surfaced a rotation advisory naming a specific log, that's the one to rotate.

**Sanity rule:** never rotate another agent's log on the user's verbal request alone — rotation rewrites a log, and rewriting another agent's memory violates the cross-agent courtesy rule. If the user means another agent, ask them to switch to that agent (or have that agent run rotation themselves).

## Framework upgrade vocabulary (universal)

When a newer skill version is available (or the user wants to check), these phrases trigger the upgrade flow.

**User says** (any of):
- "update the framework" / "upgrade the collab framework"
- "get the latest version" / "pull the latest"
- "check for updates and apply"
- "update multi-agent-collab"
- "is there a new version" (this one runs the check only — no apply)

**Agent action:**
1. Run `bash scripts/collab-check.sh` first — its update advisory reports if a newer version exists. If "is there a new version" was the trigger, stop here and report.
2. Run `npx @gpgaoplane/multi-agent-collab init` (or `bash <local-clone>/scripts/collab-init.sh` if working from a local clone). Migration prompts appear.
3. After migration completes, follow the **post-upgrade ritual** below: read `.collab/UPGRADE_NOTES.md`, re-read `AI_AGENTS.md` `behavioral-rules`, then run `bash scripts/collab-init.sh --ack-upgrade`.

**Sanity rule:** if the working tree is dirty, the upgrade will block (M2 cleanliness check). Commit or stash uncommitted work before triggering an upgrade.

## Post-upgrade ritual

When the framework is upgraded (a `collab-init` run produced `.collab/UPGRADE_NOTES.md`), the first agent to enter the next session must:

1. Read `.collab/UPGRADE_NOTES.md` in full — it contains the `>>> Upgrade summary:` from each migration that ran, plus a pointer to CHANGELOG.md.
2. Re-read `AI_AGENTS.md` `behavioral-rules`. Behavior contracts may have changed. **Ignore your watermark for this one read** — read the body, not just the frontmatter.
3. If a summary calls out a breaking change, propagate any required state changes to your own `state.md` before the next substantive write.
4. Acknowledge with `bash scripts/collab-init.sh --ack-upgrade` to archive `UPGRADE_NOTES.md`. This signals other agents that the upgrade has been absorbed; they do not need to re-process it.

`collab-check` surfaces the presence of `UPGRADE_NOTES.md` at the top of its output as a reminder.
