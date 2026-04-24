---
status: active
type: reference
owner: shared
last-updated: 2026-04-24T00:00:00-04:00
read-if: "you are setting up stronger receipt enforcement for any repo using this skill"
skip-if: "you want the soft-warning default and do not need hard-fail enforcement"
---

# Optional Enforcement Hooks

## Portable pre-commit receipt hook (v0.3.0+)

The portable hook works for any agent that writes to `docs/agents/<name>.md`. It ships in every install at `scripts/hooks/pre-commit` and is installed into `.git/hooks/` via the `--install-hooks` flag:

```bash
# At bootstrap time:
npx @gpgaoplane/multi-agent-collab init --install-hooks
# Or via the bundled bash script:
bash scripts/collab-init.sh --install-hooks
```

Behavior:

- Runs on every commit. For each staged change under `docs/agents/*.md`, it invokes `scripts/collab-verify-receipt.sh`.
- The verifier checks that the staged diff **adds** a new `### Task Receipt` heading. Stale receipts from prior commits do not satisfy the check (this is the diff-based improvement over v0.1.0's presence-based check).
- Default mode: **soft-warn** — prints a warning to stderr and allows the commit. Controlled by `.collab/config.yml`:

  ```yaml
  strict: false  # default — warn only
  strict: true   # hard-fail; commit is rejected when a receipt is missing
  ```

- Preserves any pre-existing `.git/hooks/pre-commit` as `.git/hooks/pre-commit.local` and delegates to it after the managed check. Re-running `--install-hooks` is idempotent.
- Detects its own installation via the `# collab:managed-hook` sentinel on line 2 of the hook — this is how idempotency avoids clobbering a user hook on re-run.

Uninstall:

```bash
rm .git/hooks/pre-commit
# Restore your original hook if one was preserved:
mv .git/hooks/pre-commit.local .git/hooks/pre-commit
```

## Legacy Claude-only hook (v0.1.0)

Location: `templates/optional/claude-pre-commit-receipt.sh`

Shipped with v0.1.0 for Claude-only repos, before the portable verifier existed. Still present for backward compatibility. Prefer the portable hook above for any new install.

Install (if you need the legacy behavior specifically):

```bash
cp templates/optional/claude-pre-commit-receipt.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Differences from the portable hook:
- Only enforces on `docs/agents/claude.md`.
- Presence-based detection: accepts any historical `### Task Receipt` block in the file. A commit that does not add a new receipt but has a past one in the file passes. The portable hook rejects this.
- No `strict`/warn distinction; always hard-fails.

Disable either hook: `rm .git/hooks/pre-commit`.
