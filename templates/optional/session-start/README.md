# Session-Start Snippets (optional)

Auto-surface remote drift at session start. Install per-agent:

## Claude Code

Merge the JSON into your project or user `settings.json`:

    jq -s '.[0] * .[1]' ~/.claude/settings.json session-start/claude-settings.json > /tmp/merged && mv /tmp/merged ~/.claude/settings.json

Or add the `SessionStart` block manually. See Claude Code docs for settings.json structure.

## Codex CLI

Codex reads hooks from `~/.config/codex/hooks/session-start.sh`. Install:

    mkdir -p ~/.config/codex/hooks
    cp codex-hook.sh ~/.config/codex/hooks/session-start.sh
    chmod +x ~/.config/codex/hooks/session-start.sh

## Gemini CLI

Gemini's session lifecycle is limited. Run manually at session start:

    git fetch --all --quiet && git log --oneline origin/$(git rev-parse --abbrev-ref HEAD)..HEAD | head -5

Or document it in the project `GEMINI.md` as a session-start ritual.

## What to expect

When remote is ahead, you'll see the commits that have landed since your last session. When you are ahead, you'll see your unpushed commits. When in sync, the output is empty.

Cost: one `git fetch` per session start (cached + cheap on a warm network).
Opt out: remove the hook.
