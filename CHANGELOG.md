# Changelog

## 0.4.1 — 2026-04-26

Additive patch. No state changes; re-init is sufficient on upgrade.

### Added
- **`default_agent` key in `.collab/config.yml`.** Optional, opt-in. New tier 3 in the detection ladder: `--agent` flag → `$COLLAB_AGENT` → `config.yml: default_agent` → env probe → hard-fail. Zero false positives — explicit user setting per repo, persistent across shells, auditable in git.
- **`collab-init --prune-backups [--keep N]`.** Deletes old `.collab/backup/<timestamp>/` directories beyond the most recent N (default 5; or `keep_recent_backups` from `.collab/config.yml`).
- **Auto-prune on `--ack-upgrade`.** After acking an upgrade, old backups beyond `keep_recent_backups` are pruned automatically. Keeps `.collab/backup/` self-cleaning without manual intervention.
- **Migration `0.4.0-to-0.4.1.sh`.** Pure no-op summary; emits `>>> Upgrade summary` so users see what changed.
- **14 new test cases** in `tests/test-v041-features.sh` covering default_agent precedence (flag > env > config > probe > hard-fail), --prune-backups with explicit --keep, default from config, exceeds-count no-op, no-backup-dir graceful, ack-upgrade auto-prune.

### Changed
- **Hard-fail message expanded.** Mentions the `default_agent` config option and warns that the Codex/Gemini env-var probes are best-effort (they can match config/auth env vars set globally without an active session). `CLAUDECODE` is the only strong active-session signal.

### Notes for users on v0.3.0 or earlier
This is an additive patch. Run `npx @gpgaoplane/multi-agent-collab init` and the migration chain will apply 0.3.0→0.4.0→0.4.1 in order. The 0.4.0 release notes still apply.

## 0.4.0 — 2026-04-26

### Changed (breaking)
- **Bootstrap installs only the calling agent (Group A).** `collab-init` no longer pre-seeds all three first-class adapters. Detection precedence: `--agent <name>` → `$COLLAB_AGENT` → env-var probe (`CLAUDECODE`, `CODEX_HOME`, `GEMINI_CLI`, etc.) → hard-fail with re-run guidance. Other agents arrive via `--join <name>`. `--join` and `--add-agent` are rejected on fresh installs (use `--agent` instead).
- **`AI_AGENTS.md` Current Adapters table is now dynamic** — rendered from `.collab/agents.d/*.yml` on every init/join/migration.
- **`AI_AGENTS.md` trimmed to ≤100 lines (Group G)** — verbose explanations of frontmatter, free file creation, and delta-read moved to one-line pointers into `docs/design.md` (§6.1, §6.6, §10). All load-bearing rules retained.

### Added
- **Work-log rotation (Group B).** `scripts/collab-rotate-log.sh <agent>` archives older entries to `.collab/archive/agents/<agent>-<date>.md`, replaces them in the live log with one-line Receipt summaries, preserves open handoff blocks. Defaults: 300-line threshold, 8 entries kept; configurable in `.collab/config.yml`. CRLF + `## subsection` aware. `collab-check` advises rotation when threshold exceeded.
- **Handoff vocabulary + pickup verb (Group C).** `collab-handoff pickup <id> --from <self>` prints the block summary and stamps `picked-up:` metadata. Sender + receiver phrases documented in PROTOCOL.md ("wrap up for handoff", "tag out to <agent>", "take the baton", etc.). `close`/`cancel` now search across all agent logs (receivers can close handoffs). Group `to: any` handoff explicitly tested.
- **Commit cadence rule (Group D).** New `Cadence` bullet under AI_AGENTS.md `Commits` and PROTOCOL.md `Before committing`: commit only on user request or at clean task boundaries with standing approval.
- **Post-compact persistence (Group E).** New "Post-compact ritual" subsection in AI_AGENTS.md. Optional Claude `PreCompact` hook template under `templates/optional/pre-compact/`. Inline critical rules in root `AGENTS.md` (`collab:critical-rules` block) for platforms that auto-discover only AGENTS.md.
- **Upgrade communication (Group F).** Migration scripts emit `>>> Upgrade summary:` blocks. `collab-init` writes `.collab/UPGRADE_NOTES.md` (status `transient`) capturing the migration summaries. `collab-init --ack-upgrade` archives the file (explicit ack avoids two-agent race). PROTOCOL.md gains "Post-upgrade ritual". `collab-check` surfaces UPGRADE_NOTES.md presence at top of output.
- **0.3.0 → 0.4.0 migration script.** Detects agents with seed-only work logs (no entries, no handoff blocks) and offers to prune. Default-keep when non-interactive. Honors `COLLAB_MIGRATE_NONINTERACTIVE=1`, `CI`, `COLLAB_MIGRATE_REMOVE_ALL_SEED=1`. The calling agent (`$COLLAB_AGENT`) is excluded from flagging.
- **Marker safety + migration safety (Group M).**
  - **M1.** `<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->` comments inside every framework-managed marker block.
  - **M2.** Pre-migration cleanliness check: upgrade refuses to run on a dirty working tree unless `--force-dirty` is passed. Untracked files don't block.
  - **M3.** Auto-backup on upgrade (`.collab/backup/<from>-to-<to>-<timestamp>/`). New `--no-backup`, `--restore <id>` flags.
  - **M4.** New `--diff` flag: applies migration, prints per-file unified-diff hunks, then restores the repo from backup. Lets users preview changes safely.
  - **M5.** Loud per-migration logging (BEFORE/AFTER line/marker counts via `scripts/lib/migration-log.sh`).
  - **M6.** New `collab:customization-guide` section in AI_AGENTS.md teaching the edit-OUTSIDE-markers convention with examples.
- **User vocabulary follow-ups (C7 + C8).**
  - **C7.** Log rotation phrases ("rotate the log", "trim my work log", "compact the work log") map to `collab-rotate-log.sh <self>`.
  - **C8.** Framework upgrade phrases ("update the framework", "get the latest version", "is there a new version") map to the upgrade flow.
- **`collab-register --type/--owner/--status` flags (Group H1).** Register files lacking frontmatter, or override frontmatter values when both are present.
- **`collab-check --stats` (Group H2).** Per-agent diagnostic table: entries, log lines, open handoff count, archive count. Plus total managed-file count from INDEX.
- **~196 new test cases** across new test files: `test-collab-init-upgrade-v040`, `test-collab-rotate-log`, `test-vocabulary`, `test-marker-warnings`, `test-cleanliness-check`, `test-backup-restore`, `test-migration-logging`, `test-diff-flag`, `test-ai-agents-md-cap`, `test-h-flags`, `test-upgrade-notes`. Plus extensions to existing test files.

### Documentation
- README, SKILL.md, `docs/plans/2026-04-25-v0.4.0-plan.md` reflect the calling-agent-only model, the upgrade path from v0.3.0, and the marker safety conventions.
- `CLAUDE.md` (project-level) added with permission-to-execute rules, testing discipline, and project layout reminders.

## 0.3.0 — 2026-04-23

### Added
- `collab-handoff` CLI with create/close/cancel subverbs and chain support via `parent-id`.
- `collab-catchup` preview and `ack` subverbs (two-phase watermark update).
- `collab-catchup --handoff` to surface open handoffs targeting the caller.
- `collab-presence start|end` for `.collab/ACTIVE.md` row management.
- `scripts/hooks/pre-commit` portable receipt verifier + `collab-init --install-hooks`.
- `.collab/config.yml` with `strict` and `update_channel` keys.
- Update advisory in `collab-check` (24h cache, CI-silent, config-gated).
- Optional session-start snippets at `templates/optional/session-start/`.
- GitHub Actions workflows: `test.yml` on push/PR, `publish.yml` on `v*` tag.
- Adapter wiring: `PROTOCOL.md`, `ROUTING.md`, and `ADAPTER.md` now teach handoff rituals and user vocabulary ("take the baton" / "pick up handoff").

### Changed
- Memory seed files now have visibly-intentional empty-state messages.
- `bin/cli.js` exposes `presence`, `catchup`, `handoff` subcommands.
- `collab-init.sh` upgrade path now chains intermediate migrations (v0.1.0 → v0.3.0 runs v0.1.0→0.2.0 AND v0.2.0→0.3.0).

### Documentation
- New `docs/handoff-schema.md` describes the block format and chain semantics.
- `CONTRIBUTING.md` updated with automation-token guidance for CI publish.

## 0.2.0 — 2026-04-22

- npm distribution, SKILL.md wrapper, AGENTS.md front door, generic `--join` flow.

## 0.1.0 — 2026-04-22

- Initial release: core framework, templates, per-agent adapters, scripts.
