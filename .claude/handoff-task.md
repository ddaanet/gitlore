# Task — 2026-07-30

## Current task

Executing `docs/plans/2026-07-30-13-tier-pinning-composition-projection.md` in
the gitlore repo, on `main`, in place. Steps 3, then 1+2, are committed:

- `89099f3` pin tiers at the recorded gitlink (SessionStart: unconditional
  `submodule update --init`, read-only `fetch origin live`, ancestry against
  `FETCH_HEAD` in place of the non-fast-forward discriminator, prepared-merge
  check moved ahead of the checkout, detach-in-place when a tier arrives on a
  branch).
- `6160344` composition becomes two projections; the merge adopts the tier
  (`gitlore_compose_down` / `gitlore_compose_root_bullets` / `gitlore_compose_up`
  / `gitlore_compose_orphans`; `gitlore_compose_tier_bullets`,
  `gitlore_compose_save_base`, `gitlore_git_as_gitlore` and
  `refs/gitlore/compose-base` deleted; `compose_merged_indexes` in
  `scripts/resolve.sh` rewritten to a per-adopted-tier up projection staged in
  the memory store, comparing store against memroot by `-ef`).

Step 4 (`/gitlore:merge`) is written, fully green and mutation-validated, but
**uncommitted**: `scripts/merge-memory.sh` (new, executable),
`skills/merge/SKILL.md` (new), `gitlore_merge_stores` +
`gitlore_merge_one_store` appended to `scripts/lib/resolve.sh`, the `publish`
field in `gitlore_write_merge_state` (set via `GITLORE_MERGE_NO_PUBLISH`), the
`publish = no` skip in `scripts/resolve.sh continue-after-merge`,
`gitlore.mergeCommand` seeded in `scripts/install/write-settings.sh` and
`scripts/cc-hooks/session-start.sh`, `tests/merge_memory.bats` (13 cases), plus
new assertions in `tests/plugin_distribution.bats`, `tests/write_settings.bats`
and `tests/cc_hook_session_start.bats`. `docs/design.md` is updated for all four
steps (five config keys, the `merge` component entry, tiers pinned, two
projections, the root-at-`HEAD` lookup, the three-case taking rule).

Last full run before step 4: 560 + 72 green, `lint-shell: 122 files clean`,
`check-version: in sync (0.4.3)`. Step 4's own suites ran green
(`merge_memory`, `plugin_distribution`, `write_settings`,
`cc_hook_session_start` = 43 + 12), but **`just precommit` has not run over the
step-4 tree** — the command that would have was interrupted.

## Remaining

1. Write the `docs/changelog.md` entry dated 2026-07-30 (the write was
   interrupted, so `changelog.md` is untouched). It covers: the 2026-07-29
   dogfood incident that motivated pinning; the read-only fetch and why
   ancestry replaced the refusal discriminator; composition as two projections
   and why the three-way stays in `index-merge.sh`; the root-at-`HEAD`
   disambiguation and its accepted cost (a line added and deleted inside one
   uncommitted window lingers in the carrier, reported); the two rules that fell
   out of building it (root with no line for an active tier states nothing;
   `compose_merged_indexes` never staged root's write); `/gitlore:merge` and the
   `publish: "no"` mark; and the test movement (`a dormant tier still receives
   mirror-down` deleted, the two upstream-arrival cases became adoption cases,
   five audit-chain cases deleted with the ref, deletion cases now commit first).
2. `just precommit`, then commit step 4.
3. Update `memory/ddaanet/reference_gitlore_tier_merge_direction.md` — its
   manual "apply the upstream tier lines up into root" steps are now the
   tooling's adoption step — and correct or delete
   `memory/ddaanet/reference_gitlore_bash_edit_desync.md`, whose central claim
   is false: `hooks/hooks.json:30` matches `Write|Edit|Bash`, verified this
   session. Both ride the same parent commit, with an approved summary.
4. Bump the plugin version before releasing (`check-version` in sync at 0.4.3).
5. Dogfood on this repo: `memory/ddaanet` is pinned at `f21be68` with
   `origin/live` ahead at `788f61d` — a live fast-forward-plus-adoption target
   for `/gitlore:merge`.

## Open decisions

Four calls made beyond the plan's text, all implemented and tested, none yet
confirmed by David:

- The down projection is **skipped** when root holds no line for an active tier,
  and the layout adopts that tier's carrier instead. Without it, a
  deactivate/reactivate round trip reads root's stripped block as deletions and
  empties the carrier. It also means emptying a tier's block in root does not
  drop the tier — deactivation is the way to do that.
- A memory-store merge runs a layout-only pass (`gitlore_compose_up` with no
  tier named) rather than no pass at all, so the merged root index still gets
  the layout, the four validations and the dangling report.
- The non-diverged fast-forward in `/gitlore:merge` adopts **without** a
  merge sub-agent. Pinning removed the only mechanism that took upstream facts,
  and routing a fast-forward through a synthesis would make taking them
  expensive enough to skip.
- The no-publish intent rides the state file as `publish: "no"` rather than a
  new flavor or a marker file; every gate leaves it empty.

Still open from the previous session, untouched: `memory/MEMORY.md` is 22.4KB
against a 17.1KB soft target; whether to carry out the `docs/plans/` → root
`plans/` migration; placing the five `brief-*.md` files at the repo root (one,
`brief-hook-exec-and-compose-revert.md`, appeared during this session and is
not mine).