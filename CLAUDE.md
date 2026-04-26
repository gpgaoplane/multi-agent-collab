# multi-agent-collab — Project Instructions

## Testing rules (HARD)

- **Never run the full test suite for single-file changes.** `tests/run-all.sh` takes 60–90s; running it after edits that can't possibly affect other tests is waste. Run only the affected test file.
- **Never run any test suite after docs-only changes.** README/CHANGELOG/SKILL.md edits cannot break code.
- **Run the full suite only when:**
  - A shared script changes (`scripts/lib/*`, `harness.sh`, `collab-init.sh` after a behavior change)
  - A version bump touches templates/collab/VERSION
  - Right before tagging a release
- **Stop polling background commands.** The system already notifies on completion. No `until ... sleep 5; done` loops.

## Project layout reminders

- **Calling-agent-only invariant (v0.4.0+).** `collab-init.sh` fresh mode bootstraps only the agent resolved by the detection ladder (`--agent` → `$COLLAB_AGENT` → env probe → hard-fail). Never re-introduce auto-seeding of all descriptors.
- **Test harness defaults to claude.** `tests/harness.sh` exports `COLLAB_AGENT="${COLLAB_AGENT:-claude}"`. Tests that need multiple agents call `init_with_all_agents <repo>`.
- **Marker-guided merge is sacred.** Anything between `<!-- collab:NAME:start/end -->` is owned by the templates and rewritten on re-init. Anything outside is user content and must survive.
- **Test files own their tmp repos.** Use `make_tmp_repo` from harness, clean up at end. Don't leak state between test files.

## Plan tracking

Active plan: `docs/plans/2026-04-25-v0.4.0-plan.md`. Group A complete; Groups B-H pending. Ship steps (X1-X6) at end include version bumps already done partially (templates/collab/VERSION, package.json, SKILL.md = 0.4.0).

## What this skill does

Bootstraps multi-agent AI collaboration into any git repo. Pure-bash bootstrap with thin Node.js shim. Five mechanisms: shared contract + per-agent adapters, core-five memory model, fan-out routing matrix, End-of-Task Receipt, two-tier session/task model. Read `docs/design.md` for full rationale.
