# Handoff Block Schema

A handoff block is a markdown section appended to a sender agent's work log when they finish a substantive chunk of work and want another agent to validate, extend, or take over.

## Parse contract

Each block is delimited by the lines:

    <!-- collab:handoff:start id=HANDOFF_ID -->
    ...
    <!-- collab:handoff:end -->

The header inside each block is a bullet list with stable keys:

- `handoff-id`: monotonic `YYYYMMDD-HHMMSS-<4hex>` — unique per handoff.
- `parent-id`: previous handoff id in the chain, or `none`.
- `from` / `to`: agent names matching `.collab/agents.d/<name>.yml`.
- `branch`: git branch active when the handoff was written.
- `at`: ISO-8601 timestamp.
- `status`: `open` when written; `claimed` when receiver acknowledges; `closed` when the receiver's task ships.

## Status transitions

    open → claimed       # receiver runs `collab-catchup --handoff --claim <id>`
    claimed → closed     # receiver runs `collab-handoff close <id>` or the next handoff cites this one as parent-id
    open → cancelled     # sender runs `collab-handoff cancel <id>`
    claimed → cancelled  # receiver claimed and then determined the work is invalid; run `collab-handoff cancel <id>`

Blocks are **append-only** except for the status line, which is updated in place.

## Chains

Handoffs form a linked list via `parent-id`. `A → B → C → A` is four blocks with:

    id=1, parent-id=none (A finishes initial work, targets B)
    id=2, parent-id=1    (B finishes validation/extension, targets C)
    id=3, parent-id=2    (C finishes review, targets A)
    id=4, parent-id=3    (A finishes final polish, targets done)

`collab-catchup --handoff` surfaces the newest open block targeting the current agent or `any`.
