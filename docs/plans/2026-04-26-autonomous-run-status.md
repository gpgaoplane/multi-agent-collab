---
status: active
type: investigation
owner: claude
last-updated: 2026-04-26T00:00:00-05:00
read-if: "you are the user reviewing the autonomous v0.4.0 run, or you are continuing this work"
skip-if: "the v0.4.0 plan has been merged and tagged"
related: [docs/plans/2026-04-25-v0.4.0-plan.md]
---

# v0.4.0 Autonomous Implementation Run — Status

This file is updated continuously during the autonomous run so progress is durable across compaction or interruption. Read top-to-bottom to see what was done, in order, with any assumptions or blockers called out.

## Self-rules adopted for this run

1. Commit per group with descriptive messages on `main`.
2. Stop-on-failure: 2 retries, then log here and continue with next independent group.
3. No further Plan-agent reviews — plan-as-written.
4. Test scope discipline: single-file changes → single-file tests; full suite only on shared-code changes or pre-ship.
5. **No git tag pushed.** Version bumps + CHANGELOG, but `v0.4.0` tag is the user's call — it triggers npm publish.
6. Conservative defaults on plan-ambiguous cases; log assumption + rationale here.

## Run log

(updated as work progresses — newest at the bottom)

### 2026-04-26 — Autonomous run, partial completion

**Pushed to origin/main, in order:**

| Group | Commit | Summary |
|---|---|---|
| A | `8db15c7` | Bootstrap installs only the calling agent. Hard-fail on no detection. Migration prunes unused agents. Dynamic adapter table. |
| D | `1ee21ae` | Commit cadence rule in AI_AGENTS.md + PROTOCOL.md. Re-init refreshes the rule. |
| C | `49cc210` | Handoff vocabulary (sender + receiver phrases). New `pickup` verb. close/cancel now search across all agent logs. `to: any` test. |
| E | `571670d` | Post-compact ritual subsection. Optional pre-compact hook template. AGENTS.md gets inline critical rules. |
| B | `53a9b32` | `collab-rotate-log.sh` with 300-line default, 8 entries kept, CRLF + subsection-aware splitting. Open handoffs preserved. collab-check advisory. |
| F | `03b645f` | Migration scripts emit `>>> Upgrade summary:` blocks. Upgrade flow writes `.collab/UPGRADE_NOTES.md`. New `collab-init --ack-upgrade` flag. PROTOCOL.md post-upgrade ritual. |

**Test count gain:** ~80 new test cases. All passing on origin/main as of last commit.

**Versions bumped:** `package.json`, `templates/collab/VERSION`, `SKILL.md` all at `0.4.0`. CHANGELOG has the v0.4.0 header and the Group A/D entries; entries for C/E/B/F/G/H pending.

### Deferred — pick up next week (weekly quota reset 2026-05-03)

**Group G — trim AI_AGENTS.md to ≤100 lines.** Current is 133 lines. Plan calls to move verbose explanations of frontmatter, free file creation, and delta-read into `docs/design.md` (already `reference-only`), keeping load-bearing rules + section pointers in AI_AGENTS.md. Add a snapshot test for the 100-line cap.

**Group H — small folded-in items.**
- H1: `collab-register --type <t> --owner <o>` flags for files lacking frontmatter.
- H2: `collab-check --stats` (entries/agent, average log size, archive coverage).

**Ship hygiene.**
- CHANGELOG.md entries for groups C, E, B, F, G, H (D and A done).
- README.md "What's new in v0.4.0" expansion to mention B/C/E/F/G.
- `v0.4.0` git tag — your call. Tag triggers npm publish via the existing GitHub Action.

### Assumptions made during the run (with rationale)

1. **A1 detection probes a fixed env-var list.** I picked `CLAUDECODE`, `CLAUDE_CODE_SSE_PORT`, `CLAUDE_CODE_OAUTH_TOKEN` for Claude; `CODEX_HOME`, `CODEX_CLI` for Codex; `GEMINI_CLI`, `GEMINI_API_KEY`, `GOOGLE_AI_API_KEY` for Gemini. Reasoning: these are the strongest CLI-specific signals I could verify; broader API keys (e.g. `ANTHROPIC_API_KEY`) were excluded because they exist in many users' general environments without indicating an active CLI session. **You may want to widen the list** if real-world detection misses cases.
2. **C3 pickup prints summary instead of writing receiver's `state.md` directly.** Plan-agent flagged the auto-write as risky (cross-agent memory write). Pickup prints the block to stdout; the receiver agent paste-writes it manually. This is more conservative and aligns with the existing "do not edit another agent's memory" rule.
3. **B's rotation script ignores `<!-- collab:log-live -->` markers.** Initial design used live-region markers, but agents in practice append at end-of-file (after `## Handoff blocks`). I switched to "scan the whole file for ISO-timestamped entry headers" — simpler and matches existing append behavior. Open handoff blocks are preserved in place.
4. **B's threshold default is 300 lines, keep_recent default is 8.** Per your earlier guidance.
5. **F's `--ack-upgrade` is explicit, not side-effectful on read.** Plan-agent flagged the implicit-archival approach as race-prone. The current design: agent reads UPGRADE_NOTES.md, runs the post-upgrade ritual, then runs `collab-init --ack-upgrade` to archive it. Two concurrent agents will see "already archived" on the second one — graceful.
6. **The 0.3.0→0.4.0 migration excludes the calling agent (`$COLLAB_AGENT`) from seed-only flagging.** The agent currently running collab-init is by definition wanted; pruning them would be self-destructive.
7. **`COLLAB_MIGRATE_REMOVE_ALL_SEED=1` exists as a non-interactive opt-in for scripted "yes-to-all" pruning.** Tests use it. Documented as destructive.
8. **`tests/harness.sh` defaults `COLLAB_AGENT=claude`.** Required after A1 changes — without a default, every existing test would hard-fail on `bash scripts/collab-init.sh` with no args. The harness export keeps backward compat for tests that pre-date Group A.
9. **`init_with_all_agents` helper added to harness.sh** for tests that genuinely need multi-agent state (handoff, catchup, presence, etc.). Used by ~5 test files.
10. **No git tag pushed, ever.** Per the explicit instruction in CLAUDE.md and the autonomous-run rules. You sign off on the v0.4.0 tag — that's what triggers npm publish.

### Open questions for you to decide

1. **Do you want to ship v0.4.0 with just A/D/C/E/B/F (current state on origin/main), or wait for G/H?** Functionally A–F is a complete release; G is a quality-of-life trim and H is small polish. Both could ship in v0.4.1.
2. **Detection ladder — env-var list adequate?** See assumption 1. If you've been frustrated by the Claude/Codex/Gemini CLIs not setting the vars I picked, name the right ones and I'll adjust in a follow-up.
3. **CHANGELOG and README — handle now or defer to v0.4.1 release prep?** Both are small. Could be done by another agent as a "ship prep" task without much risk.
4. **The Plan-agent critique surfaced six concerns; all six were addressed.** Worth re-reviewing? Probably not — every concrete fix is in code and tested.

### Quick-resume instructions for next week

When you're ready to continue:

```
read docs/plans/2026-04-26-autonomous-run-status.md and docs/plans/2026-04-25-v0.4.0-plan.md.
A through F are committed on origin/main. Pick up at Group G:
trim templates/AI_AGENTS.md to ≤100 lines, move verbose explanations
to docs/design.md, add a snapshot test, then H1 (collab-register flags)
and H2 (collab-check --stats), then CHANGELOG + README + tag.
```

That single prompt is enough to re-orient a fresh session.

---

## Summary for human review

**Six of seven main groups (A, D, C, E, B, F) are complete, tested, and pushed to origin/main.** ~80 new test cases, all green. v0.4.0 versions are bumped across `package.json`, `SKILL.md`, `templates/collab/VERSION`. The repo is in a shippable state for an A/D/C/E/B/F release. Group G (AI_AGENTS.md trim) and Group H (small folded-in items) are deferred to next week's quota window. v0.4.0 git tag is your call — not pushed.

The autonomous run met its primary goal — substantial v0.4.0 work is durable on origin and reviewable when you wake up.

---

### 2026-04-26 (later) — full v0.4.0 run completed

After the user clarified that quota was fully refreshed, the rest of the plan was executed in order: G, then C7+C8 vocabulary follow-ups, then Group M (M1–M6 marker preservation + migration safety), then Group H, then docs sweep. Plan-doc amendment also pushed.

**Commits added on origin/main since the prior summary:**

| Item | Commit | Title |
|---|---|---|
| Plan amendment | `2b2ce24` | Plan amendment: C7, C8, Group M |
| C7 + C8 | `079d6a4` | Rotation + upgrade user vocabulary |
| M1 + M6 | `dd8f805` | Marker warnings + customization guide |
| M2 | `998247d` | Pre-migration cleanliness check |
| M3 | `0f1f6f6` | Backup + restore around upgrades |
| M5 | `aaea892` | Loud per-migration logging |
| M4 | `142727d` | --diff flag for migrations |
| Group G | `ce7caac` | Trim AI_AGENTS.md to 100 lines |
| Group H | `33a179e` | collab-register flags + collab-check --stats |

**Test totals:**
- ~196 total new test cases across the v0.4.0 run.
- Full suite green (last run before this summary). One residual fix made post-suite: `test-backup-restore` had a stale assertion that expected AI_AGENTS.md to differ between backup and post-upgrade live; replaced with a structurally-correct VERSION-differential assertion.

**Plan vs implementation deviations (logged for transparency):**
1. **C3 (handoff pickup)** — plan said write into receiver's state.md; implementation prints to stdout + stamps `picked-up:` (Plan-agent's safety recommendation). User approved.
2. **B3 (work-log markers)** — plan said `log-live` and `log-archived-summary` markers; implementation kept only `log-archived-summary` because agents append at end-of-file in practice. Rotation script scans by ISO-timestamp regex regardless of markers.
3. **M1 (marker warnings)** — INDEX.md and ACTIVE.md auto-managed table blocks intentionally skipped. ADAPTER.md `platform-notes` also skipped (it's user-editable scope, not framework-managed).
4. **G2 (trim cap)** — hit exactly 100 lines (plan target). The customization-guide example uses an `example:section-name` placeholder rather than a real marker name to avoid confusing the duplicate-marker test.
5. **`AI_AGENTS.md` trim path** — `refresh_managed_sections` only refreshes existing sections; it does NOT auto-add new marker blocks (e.g. `customization-guide`) on re-init. Documented in test as expected behavior. Users on v0.3.0 → v0.4.0 will get the new block via the migration's `re_init_shared` path → AI_AGENTS.md is ULTIMATELY refreshed because it's a single-template-source rewrite, not a section-by-section refresh — but on a re-init within v0.4.0 that has manually stripped the customization-guide block, the block won't be re-injected. Edge case; non-blocking.

**Open questions for you:**

1. **Tag `v0.4.0` now or wait?** Tag triggers npm publish via the existing `publish.yml` GitHub Action. All work is on `main`. Recommend testing the published artifact in a real bootstrapped repo first if you're cautious; tag immediately if you trust the green test suite.
2. **Backup pruning policy?** v0.4.0 ships `--restore` but no `--prune-backups`. After multiple upgrades a repo will accumulate `.collab/backup/<timestamp>/` directories. Defer to v0.5.0? Document `git clean .collab/backup/*` as the manual workaround in the meantime?
3. **Auto-detection env-var list correctness?** The detection ladder probes `CLAUDECODE`, `CLAUDE_CODE_SSE_PORT`, `CLAUDE_CODE_OAUTH_TOKEN`; `CODEX_HOME`, `CODEX_CLI`; `GEMINI_CLI`, `GEMINI_API_KEY`, `GOOGLE_AI_API_KEY`. If real-world detection misses cases on your end (e.g. Codex CLIs that don't set those vars), name the right ones and I'll widen.
4. **Detection probe for `ANTHROPIC_API_KEY`?** I deliberately excluded this because many users have it in their general environment without indicating an active Claude Code session. If you'd like a more permissive Claude detection, say so and I'll add it.

**Things explicitly NOT done (deferred or out of scope):**
- v0.4.0 git tag (your call).
- Backup pruning command.
- The v0.5.0+ deferred items: auto-install hooks by default, presence-required mode, native Windows bash-free path, `collab-check --token-budget`, CLAUDE.md auto-management at `~/.claude` level (separate from `docs/agents/claude.md` work logs which Group B handles).

**Quick-resume prompt if you want another agent to ship v0.4.0 from here:**

```
Read docs/plans/2026-04-25-v0.4.0-plan.md and docs/plans/2026-04-26-autonomous-run-status.md.
All plan items are committed on origin/main. To ship: review the green CI on GitHub,
then push git tag v0.4.0 to trigger npm publish via .github/workflows/publish.yml.
Verify the published package's README and CHANGELOG read correctly. If anything
looks off, the auto-backup mechanism (M3) lets you sandbox-test by upgrading a
copy with --diff first.
```

That single prompt is enough to ship v0.4.0 cleanly.

