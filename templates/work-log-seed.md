---
status: active
type: work-log
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you need to see {{AGENT_DISPLAY}}'s recent work and watch-outs"
skip-if: "status != active or last-updated <= your watermark"
---

# {{AGENT_DISPLAY}} Work Log

## Onboarded: {{ONBOARD_DATE}}

**Platform:** {{AGENT_DISPLAY}}
**Adapter file:** {{ADAPTER_PATH}}
**First task:** (first entry below)

---

<!-- collab:log-archived-summary:start -->
<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->
<!-- Older entries collapse to one-liners here on rotation; full history in
     .collab/archive/agents/{{AGENT_NAME}}-<date>.md -->
<!-- collab:log-archived-summary:end -->

<!-- new entries appended below, newest last -->

## Handoff blocks

When you finish a substantive chunk of work and want another agent to take over,
run `collab-handoff <to-agent>`. It appends a structured block at the end of this
log with a stable id, what you did, files touched, and the branch state. See
`docs/handoff-schema.md` for the full format.

When the work log exceeds `rotate_at_lines` (default 300, see `.collab/config.yml`),
run `./scripts/collab-rotate-log.sh {{AGENT_NAME}}` to archive older entries.
Receipts and open handoff blocks are preserved; archived entries collapse to
one-line summaries in the archived-summary marker block above.
