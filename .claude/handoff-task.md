## Current task

Execute the D17 slice 3-ii composition plan,
`docs/plans/2026-07-21-12-tiered-memory-3ii-composition.md` (four tasks, full
code in every step). Spec:
`docs/superpowers/specs/2026-07-21-tier-index-composition-design.md`.

- **Task 1** — read-only half: parsing, attribution, four validations
  (`scripts/lib/index-compose.sh`, `tests/index_compose.bats`). Two red-green
  cycles, two commits, one dispatch.
- **Task 2** — the compose pass: mirror down, splice up, byte-idempotent.
- **Task 3** — both callers: the `PostToolBatch` hook + `hooks.json`, and
  `session-start.sh` + the routing-guidance rewrite.
- **Task 4** — **inline, do not dispatch.** Full gate, design-doc D17 status +
  changelog row, and a dogfood against the live store whose Step 4 asks whether
  a real diff is a composition or a bug.

Execution mode was being chosen when this was written: Tasks 1-3 by subagent
with review between each, Task 4 by the session owner. David has not confirmed
that split — ask before dispatching.

Commits so far this session (all docs, no code yet): `1ab7fcc` spec, `c782da8`
plan, `72cb948` plan collapsed six tasks → four. Memory committed at `a2fd733`
(tier `6473a73`); the parent's memory gitlink rides the next parent commit.

`memory/ddaanet/MEMORY.md` now carries its first real bullet
(`reference_sandbox_git_lockfile`), so Task 4's dogfood exercises splice-up
against live data instead of no-opping on a bulletless carrier.

## Open decisions

- **Presence-authority: is the file set or the index authoritative over a
  pointer line's presence?** Coverage, prune, and dedup all wait behind this.
  Needs log evidence of how presence actually drifts; the standing instruction
  is to decide on that evidence rather than let inaction pick. Slice 3-ii is
  deliberately built so as not to prejudge it — mirror-down is unconditional
  precisely so no file-existence check smuggles in an answer.
- **Tier divergence is detected but not resolvable.** The resolve continuation
  derives its store from `gitlore_memory_path`, so it cannot target a tier; the
  state file would have to carry the store path. Not in 3-ii.
- **`/gitlore:resolve` does not compose.** An index merged by the resolve
  continuation composes on the next batch or next session. Recorded as a
  follow-up in the plan; no code in this slice.
- **Whether `release` should depend on a plugin-defined `prerelease` upstream.**
  Today `release` depends on `precommit` alone, since that dependency lives in
  the vendored `plugin-dev/release.just`, so releases go `just prerelease
  release`. The fix belongs in `ddaanet/claude-plugin-dev`, not this repo's
  vendored copy.
- **Happy-path evals for the tier flow** — queued for after slice 3 completes,
  per the standing instruction to write them once nested memory is done.
