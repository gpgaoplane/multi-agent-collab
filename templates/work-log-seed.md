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

<!-- new entries appended below, newest last -->

## Handoff blocks

When you finish a substantive chunk of work and want another agent to take over,
run `collab-handoff <to-agent>`. It appends a structured block at the end of this
log with a stable id, what you did, files touched, and the branch state. See
`docs/handoff-schema.md` for the full format.

