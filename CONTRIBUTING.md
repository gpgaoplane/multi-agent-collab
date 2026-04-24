# Contributing to multi-agent-collab

## Scope

This skill is intentionally small. Before opening a PR, read `docs/design.md` — especially §19 "What we deliberately don't build." If your change adds enforcement, locking, or cross-repo sync, it likely belongs elsewhere.

## Running tests

```bash
./tests/run-all.sh
```

All tests must pass before merge. TDD is required for new scripts.

## Commit style

- Imperative mood: "add X", not "added X"
- One logical change per commit
- Reference the task in `docs/plans/*.md` when applicable

## Adding a new script or template

Scripts follow TDD: write the failing test, verify red, implement, verify green, commit. See `docs/plans/2026-04-22-multi-agent-collab-implementation.md` for the pattern. Templates are inert content — cover them via integration tests (`tests/test-collab-init-*.sh`) rather than per-file unit tests.

## Reporting issues

Open a GitHub issue. For behavior mismatches vs `docs/design.md`, quote the section.

## Release process

1. Bump version in `package.json` and `templates/collab/VERSION` (must match).
2. Update `CHANGELOG.md` with user-facing changes.
3. Commit: `chore: release vX.Y.Z`.
4. Tag: `git tag vX.Y.Z` and push `git push origin vX.Y.Z`.
5. GitHub Actions `publish.yml` runs the test suite, verifies tag↔version, and publishes.

### NPM_TOKEN setup

The `NPM_TOKEN` secret must be an **automation token**, not a user-level one:

1. https://www.npmjs.com/settings/gpgaoplane/tokens → **Generate New Token**.
2. Type: **Automation** (bypasses 2FA/WebAuthn — required for CI).
3. Scope: publish for `@gpgaoplane/multi-agent-collab`.
4. Copy the token (shown once).
5. GitHub repo → Settings → Secrets → Actions → New secret named `NPM_TOKEN`.

Browser-WebAuthn tokens will fail in CI with HTTP 403.
