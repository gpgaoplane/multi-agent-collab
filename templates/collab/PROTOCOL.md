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

## Trivial-task short form

If the task hit 0 or 1 fan-out rows (read-only exploration, clarification, lookup):

```markdown
### Task Receipt
Updates: none applicable (<short reason>)
```

The Protocol still runs — the short form is an assertion that the walk was performed and produced no required writes.
