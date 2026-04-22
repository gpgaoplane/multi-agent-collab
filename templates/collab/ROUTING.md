---
status: active
type: routing
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are closing out a task and need to decide what to update"
skip-if: "you are in the middle of a task, not at its end"
---

# Fan-Out Routing Matrix

A substantive task typically hits 3–6 rows. Hit every row that applies.

| # | Dimension the task touched | Required update this turn |
|---|---|---|
| 1 | Wrote or changed code | `docs/agents/<you>.md` — new dated entry with Receipt |
| 2 | Created a plan or design artifact | `docs/plans/YYYY-MM-DD-<topic>-{design,implementation}.md` + cross-link in `decisions.md` |
| 3 | Chose between alternatives | `.<agent>/memory/decisions.md` — append entry |
| 4 | Altered architecture or introduced an invariant | `.<agent>/memory/decisions.md` + `.<agent>/memory/context.md` (if new invariant) |
| 5 | Discovered a non-obvious durable truth | `.<agent>/memory/context.md` — append entry |
| 6 | Hit a recurring bug / gotcha / workaround | `.<agent>/memory/pitfalls.md` — append entry |
| 7 | Session state changed (branch, active task, pause, next step) | `.<agent>/memory/state.md` — overwrite affected sections |
| 8 | Tracked project task changed status | `docs/STATUS.md` — update managed section |
| 9 | Created any new document | Frontmatter added + `.collab/INDEX.md` — append row |
| 10 | Cross-agent risk to flag | `docs/agents/<you>.md` — explicit `Watch out:` block |

Core rule: **hit every row that applies, not the "most important" one.** Over-update beats under-update. Stale is fixable; missing is silent data loss.
