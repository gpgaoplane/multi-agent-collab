# Pre-Compact Hook (optional)

Claude Code's auto-compaction collapses the conversation history when context fills. The summary preserves the user's intent and your recent reasoning at a high level, but specific tool results, file contents, and in-flight protocol state often don't survive. Without a reminder, the resumed session may skip the Onboarding Checklist or forget to emit a Receipt.

This optional hook fires on the `PreCompact` event and emits a system message pointing the agent at the Post-compact ritual subsection of `AI_AGENTS.md` before context is collapsed.

## Claude Code

Merge this into your project or user `settings.json`:

```bash
jq -s '.[0] * .[1]' ~/.claude/settings.json claude-settings.json > /tmp/merged && mv /tmp/merged ~/.claude/settings.json
```

Or paste the `PreCompact` block manually. See `claude-settings.json` for the exact structure.

## Codex / Gemini / others

Codex's session lifecycle does not currently expose a `PreCompact` equivalent. Agents on those platforms should follow the Post-compact ritual on their own — the rule is in `AI_AGENTS.md`.

## What to expect

When auto-compaction fires, you'll see a one-line system message:

```
post-compact: re-read AI_AGENTS.md behavioral-rules and your state.md before next substantive write.
```

That single line is enough to re-orient the model after compaction.

## Cost

Zero. The hook only fires on compact events.

## Opt out

Remove the `PreCompact` block from `settings.json`.
