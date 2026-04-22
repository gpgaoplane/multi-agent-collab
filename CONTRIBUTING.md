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
