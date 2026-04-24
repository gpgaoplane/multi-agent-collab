# Changelog

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
