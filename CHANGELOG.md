# Changelog

## 0.4.3 — 2026-05-04

Single-trigger upgrade ergonomics. v0.4.0–v0.4.2 built every preservation mechanism a downstream-project upgrade needs (cleanliness gate, auto-backup, marker-guided merge, migration sentinels, UPGRADE_NOTES auto-archive, byte-equivalent restore). v0.4.3 wraps those layers behind a single `update` subcommand and tightens the user-vocabulary contract in PROTOCOL.md so agents and humans both have one canonical entry point. Mostly additive; one genuinely new state-management behavior in `update --rollback` (sentinel cleanup, see Fixed below).

### Added

- **`update` subcommand** — `npx @gpgaoplane/multi-agent-collab update` (or `bash scripts/collab-update.sh` for local-clone use). Wraps the existing `init` upgrade flow with a pre-flight version check, interactive confirmation prompt, sentinel-aware migration count display, and post-flight ack reminder. Introduces ZERO new preservation mechanisms — every safety layer (cleanliness check, auto-backup, migration sentinels, marker-guided merge, UPGRADE_NOTES auto-archive, byte-equivalent restore) is inherited from `collab-init.sh` unchanged. Modes: `update`, `update --check`, `update --ack`, `update --rollback`. Modifier flags: `--yes` / `-y`, `--diff-first`, `--no-backup`, `--force-dirty`. The script re-execs `init` for the actual upgrade work; it does not source it.
- **`scripts/lib/semver.sh`** — extracted `version_le` from `collab-init.sh`. Adds `version_lt` and `version_eq` helpers. Numeric three-part compare (avoids the v0.10.0 lex bug). `collab-init.sh` and `collab-update.sh` both source this lib instead of duplicating the function.
- **`scripts/lib/migrations.sh`** — extracted `ensure_migration_dir`, `write_migration_sentinel`, `is_migration_applied`, `backfill_legacy_sentinels` from `collab-init.sh`. Lets `collab-update.sh` inspect sentinel state without sourcing init's body (which would re-execute its top-level mode dispatch).
- **`bin/cli.js update` case** — new switch case routes `update` to `scripts/collab-update.sh`. Forwards `rest` for full flag pass-through (same pattern as v0.4.2 G2 fix). USAGE string updated.
- **`scripts/migrations/0.4.2-to-0.4.3.sh`** — pure no-op summary migration documenting the new subcommand, the rollback sentinel-cleanup fix, and the lib extractions. Sentinel written by the chain runner on completion.
- **41 new test cases** — `tests/test-collab-update.sh` (36 cases covering all modes, prompt branches, edge cases, and the load-bearing rollback-then-re-upgrade chain that validates sentinel cleanup); 5 new cases in `tests/test-npm-shim.sh` for the `update` subcommand routing.

### Fixed

- **`update --rollback` cleans up stale migration sentinels.** This was a latent correctness issue introduced when v0.4.2 G8 added the sentinel system: after a rollback that reverts `.collab/VERSION` from e.g. `0.4.3` back to `0.4.0`, the sentinels at `.collab/.migrations/0.4.0-to-0.4.1.applied` (etc.) survived because they're not in INDEX (G4's prune logic only touches INDEX-listed paths). The next upgrade would find sentinels with valid SHAs and silently skip every migration — `re_init_shared` would still bump `.collab/VERSION` back to shipped, producing a "ghost upgrade" with no migration bodies executed and no `UPGRADE_NOTES.md` written. For v0.4.x's no-op summary migrations the user-facing impact was just "no upgrade banner appeared, weird"; for any future migration that does real file work, this would be a data-correctness bug. `update --rollback` now parses `<from>` from the latest backup directory name (`<from>-to-<to>-<HMS>`), runs `init --restore latest` (existing M3+G4 behavior), then walks `.collab/.migrations/*.applied` and deletes any sentinel whose `dst > <from>`. Surfaced by Plan-agent critique on the v0.4.3 plan; gated by a load-bearing dogfood test that does the rollback + re-upgrade chain and asserts migration bodies actually run on the second upgrade pass.

### Changed

- **PROTOCOL.md "Framework upgrade vocabulary" section** points at the new `update` subcommand as the canonical flow. The pre-v0.4.3 3-step sequence (init → read notes → `--ack-upgrade`) is documented as the backward-compat path. New phrases recognized: "preview the upgrade" → `update --diff-first`; "roll back the upgrade" → `update --rollback`; "ack the upgrade" → `update --ack`. **Forward-only** for existing installs: `re_init_shared` treats `.collab/PROTOCOL.md` as create-once, so installs upgrading from v0.4.x to v0.4.3 keep their old PROTOCOL.md text. The functional contract is preserved (old 3-command path leads to the same end state as the new 1-command path); the new vocabulary is just shorter to type. Manual fix for existing installs: `cp $SKILL_ROOT/templates/collab/PROTOCOL.md .collab/PROTOCOL.md` (warning: blows away any user customizations to PROTOCOL.md).
- **`scripts/collab-init.sh`** is shorter — `version_le` (v0.4.2 G8) and the four migration sentinel helpers (also v0.4.2 G8) move out of `collab-init.sh` into the two new libs. `collab-init.sh` sources both libs and contains no inline copies. Pure refactor; no behavior change. Existing tests pass unchanged.

### Notes for users on v0.4.2

```bash
# Once on v0.4.2+, prefer the new 'update' command:
npx @gpgaoplane/multi-agent-collab update
# Or with explicit confirm-skip for CI:
npx @gpgaoplane/multi-agent-collab update --yes
```

The pre-v0.4.3 multi-step `init`/`init --ack-upgrade` flow continues to work — no breaking change.

### Notes for users on v0.4.1 (cli.js flag-drop bug)

If you're still on v0.4.1, the cli.js shim silently drops every flag for `init` and `update`. Call bash directly to upgrade:

```bash
bash node_modules/@gpgaoplane/multi-agent-collab/scripts/collab-init.sh
# (later, after v0.4.2+ is installed)
bash node_modules/@gpgaoplane/multi-agent-collab/scripts/collab-update.sh
```

Once v0.4.2 is installed the cli.js shim correctly forwards flags, and from v0.4.3 onward the `update` subcommand is the canonical entry point.

### Notes for users on v0.3.0 or earlier

The full migration chain (0.3.0 → 0.4.0 → 0.4.1 → 0.4.2 → 0.4.3) runs automatically. v0.4.3 sits at the end of the chain and is purely additive. Auto-backup runs first; `update --rollback` (or `init --restore latest`) rolls back if anything looks wrong. The 0.4.0 release notes still apply for the breaking calling-agent-only bootstrap change.

## 0.4.2 — 2026-05-03

Correctness patch fixing nine post-ship issues surfaced by real-world use of v0.4.0 and v0.4.1. Mostly additive; one shipped-default change called out below. No file renames in user repos. Migrations are now idempotent — a re-run after an interrupted upgrade is a safe no-op.

### Fixed (post-ship correctness)

- **Rotation regex accepts date-only entry headers (G1).** `scripts/collab-rotate-log.sh:79` previously required a literal `T` after the date (`## 2026-04-28T...`), so logs with the more common date-only style (`## 2026-04-28 task title`) were silently never rotating regardless of file size. New regex: `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}([T ]|$)` — strict superset of the old contract; existing logs that worked still work, and date-only/freeform-suffix logs now rotate. The work-log seed template gains a worked entry-format example so future agents have a model to follow.
- **`bin/cli.js` forwards all flags to bash for `init`/`join`/`archive`/`register` (G2).** Previously these four cases silently dropped every flag, so `npx ... init -- --agent codex`, `--diff`, `--restore latest`, `--prune-backups`, `--ack-upgrade`, `--install-hooks`, `--force-dirty`, `--no-backup`, `--dry-run`, and `register --type/--owner` were all unreachable through the npm channel. Fixed by forwarding `rest` to bash like `presence`/`catchup`/`handoff` already did. New `tests/test-npm-shim.sh` cases gate the regression.
- **Pre-commit hook is self-contained (G3).** The installed `.git/hooks/pre-commit` previously hardcoded `bash scripts/collab-verify-receipt.sh`, which doesn't exist in npm-installed repos (no `scripts/` dir). Every staged `docs/agents/*.md` was reported as "lacks a Task Receipt" — soft-warn noise normally, hard commit blocks under `strict: true`. Restructured as template + render: `scripts/lib/receipt.sh` holds `verify_receipt()` once; `scripts/hooks/pre-commit.template` inlines it via `# {{INLINE_RECEIPT_LIB}}` substitution at install time. Result: the installed hook has zero external script dependency and works identically for npm-installed and direct-clone users.
- **`do_restore` prunes migration-created files (G4).** `--restore latest` and `--diff` (apply-then-restore) silently leaked migration side effects (new descriptors, INDEX rows, memory files) into the post-restore state. Now walks the live framework-managed file set; for any path in live but not in the backup, removes via `rm -f` (handles symlinks correctly). Strict allowlist scoped to `collect_backup_paths()`; never recursive on directories; never touches `.collab/backup/`.
- **`UPGRADE_NOTES.md` auto-archived on chained upgrades (G5).** A second upgrade run before `--ack-upgrade` previously overwrote the prior transient `UPGRADE_NOTES.md` silently — the first upgrade's notes were lost before any agent had read them. Now: before writing a new file, if a prior `status: transient` UPGRADE_NOTES exists, it's auto-archived first and a stderr notice surfaces the chain. Schema unified across both `--ack-upgrade` and the upgrade flow on `UPGRADE_NOTES-<from>-to-<to>-<YYYYMMDDHHMMSS>.md` (the date-only schema is replaced — see Changed below).
- **`.collab/VERSION` format validated (G6).** Garbage content (typo, partial corruption, `latest`) silently triggered lexicographic compare and skipped migrations. Now hard-fails with guidance at `detect_mode`, naming the bad value and pointing at `--restore latest` for recovery. The validation runs AFTER the `--restore` short-circuit, so a corrupted VERSION never locks users out of recovery.
- **Doubled marker blocks emit a loud warning (G7).** `merge_replace_section` previously silently corrupted files containing duplicate `<!-- collab:NAME:start -->` markers — the awk pass would print the body twice and leave the file in a `start, body, start, body, end` state with no diagnostic. Now counts both markers via `grep -cF`; emits `merge: WARNING <file>: marker block '<section>' is malformed (duplicate start|end markers, count=N)` to stderr and returns 1. Refresh paths in `collab-init.sh` tolerate the warning so init still completes (visible, not blocking) on already-corrupted files.
- **Migrations are idempotent via sentinels (G8).** A re-run of the migration chain (after partial failure, manual re-trigger, or any path that re-enters the upgrade flow) previously double-applied operations or failed mid-chain. Now per-migration sentinel files at `.collab/.migrations/<from>-to-<to>.applied` record successful application with an ISO-8601 timestamp and a SHA-256 of the migration script body. The chain runner skips migrations whose sentinel matches; a SHA mismatch (script body changed in a future patch) re-runs. Legacy migrations on existing v0.4.x installs are auto-back-filled on first v0.4.2 upgrade — past migrations are NOT re-run. New `scripts/lib/sha.sh` shim picks `sha256sum` / `shasum -a 256` / `openssl dgst -sha256` in order, with a "no-sha-available" graceful-degrade for minimal shells (sentinel still written; SHA mismatch detection disabled). New `version_le` helper in `collab-init.sh` is numeric three-part compare (no v0.10.0 lex bug).
- **`inject_agents_md_section` no-ops on orphan markers (G9).** If `AGENTS.md` had an orphan start marker (or end alone) — possible after a partial restore or hand-edit — the function would append a fresh block, producing the doubled-start corruption that G7 then detects on the next refresh. Now: detect orphan markers before append; emit `inject: WARNING ... orphan marker for section ... skipping append` to stderr; leave the file untouched.

### Changed

- **`rotate_keep_recent` shipped default lowered from 8 to 3** in `templates/config.yml`. Existing `.collab/config.yml` files are NOT auto-rewritten — the framework never rewrites user-owned config. Opt in by editing your `.collab/config.yml` line: `rotate_keep_recent: 3`. The change makes rotation more aggressive for new installs; old installs continue with whatever value they already have.
- **`--ack-upgrade` archive filename schema is richer.** Was `UPGRADE_NOTES-YYYYMMDD.md` (date-only); now `UPGRADE_NOTES-<from>-to-<to>-<YYYYMMDDHHMMSS>.md`. Multiple archives per day are now structurally distinct, eliminating the "same-second collision" race that the prior code handled with an "already archived" message. Same-second collisions still get a `-$$` PID suffix as a defensive uniquifier.
- **`scripts/hooks/pre-commit` renamed to `scripts/hooks/pre-commit.template`** (skill source only — no impact on installed hooks). Install-time substitution of `# {{INLINE_RECEIPT_LIB}}` produces the final hook.

### Added

- **`scripts/migrations/0.4.1-to-0.4.2.sh`.** No-op chain step that emits the `>>> Upgrade summary` block listing all G1–G9 outcomes. Writes its sentinel at `.collab/.migrations/0.4.1-to-0.4.2.applied` on completion.
- **Test files.** `test-pre-commit-portable.sh` (8 cases), `test-merge-malformed-markers.sh` (7), `test-version-validation.sh` (5), `test-inject-dedup.sh` (9), `test-upgrade-notes-chain.sh` (10), `test-migration-idempotency.sh` (19). Plus extensions to `test-collab-rotate-log.sh`, `test-npm-shim.sh`, `test-install-hooks.sh`, `test-backup-restore.sh`, `test-upgrade-notes.sh`. ~80 net new test cases.

### Notes for users on v0.4.1 (cli.js flag-drop bug)

If you're on v0.4.1, `npx @gpgaoplane/multi-agent-collab init -- --diff` and similar flag-using commands silently dropped the flag and ran the default upgrade. To upgrade safely to v0.4.2, call bash directly so flags reach the bootstrap script:

```bash
# Preview the migration without applying:
bash node_modules/@gpgaoplane/multi-agent-collab/scripts/collab-init.sh --diff

# Apply the upgrade:
bash node_modules/@gpgaoplane/multi-agent-collab/scripts/collab-init.sh

# After reading .collab/UPGRADE_NOTES.md, ack:
bash node_modules/@gpgaoplane/multi-agent-collab/scripts/collab-init.sh --ack-upgrade

# Roll back if anything looks wrong:
bash node_modules/@gpgaoplane/multi-agent-collab/scripts/collab-init.sh --restore latest
```

Once v0.4.2 is installed, the standard `npx @gpgaoplane/multi-agent-collab init -- --diff` (etc.) flow works because the cli.js shim now forwards flags correctly.

### Notes for users on v0.3.0 or earlier

The full chain (0.3.0 → 0.4.0 → 0.4.1 → 0.4.2) runs automatically. Auto-backup runs first; `--restore latest` rolls back if anything looks wrong. The 0.4.0 release notes still apply for the breaking calling-agent-only bootstrap change.

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
