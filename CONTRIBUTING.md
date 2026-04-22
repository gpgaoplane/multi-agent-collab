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

## Reporting issues

Open a GitHub issue. For behavior mismatches vs `docs/design.md`, quote the section.
