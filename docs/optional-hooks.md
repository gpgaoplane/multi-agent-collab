---
status: active
type: reference
owner: shared
last-updated: 2026-04-22T00:00:00-05:00
read-if: "you are setting up stronger enforcement for Claude-only repos"
skip-if: "you only use Codex or Gemini"
---

# Optional Enforcement Hooks

These are NOT installed by `collab-init.sh`. They ship as opt-in hardening for repos where agents have demonstrated Receipt drift.

## Claude pre-commit Receipt check

Location: `templates/optional/claude-pre-commit-receipt.sh`

Install:

```bash
cp templates/optional/claude-pre-commit-receipt.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Effect: blocks commits touching `docs/agents/claude.md` whose newest entry lacks a valid `### Task Receipt` section.

Disable: `rm .git/hooks/pre-commit` or `git commit --no-verify` (the latter only with explicit user approval).
