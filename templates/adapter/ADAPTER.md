---
status: active
type: adapter
owner: {{AGENT_NAME}}
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are {{AGENT_DISPLAY}} starting work in this repo"
skip-if: "never"
---

# {{AGENT_DISPLAY}} — Project Adapter

## First read

Read `AI_AGENTS.md` at the repo root before starting any work session. It covers project state, multi-agent rules, and shared onboarding.

## Your files

- Memory: `{{MEMORY_DIR}}/`
- Work log: `{{WORK_LOG_PATH}}`

## Platform-specific notes

<!-- collab:platform-notes:start -->
Add platform-specific pointers here (hook locations, slash commands, global vs project memory separation, etc.).
<!-- collab:platform-notes:end -->

## Handoff and pickup

When {{AGENT_DISPLAY}} finishes a handoff-worthy chunk (e.g., branch complete, major refactor done, cross-cutting change that needs review), write a handoff block:

```
./scripts/collab-handoff.sh <to-agent> --from {{AGENT_NAME}} --message "..." --files "a b c"
```

When the user says "take the baton" or "pick up handoff," run:

```
./scripts/collab-catchup.sh preview --agent {{AGENT_NAME}} --handoff
```

…and follow the instructions in the surfaced handoff block. After validation, close the handoff:

```
./scripts/collab-handoff.sh close <id> --from {{AGENT_NAME}}
```
