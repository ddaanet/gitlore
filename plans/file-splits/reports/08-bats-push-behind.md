# Split report — tests/push_behind_vs_diverged.bats

## Final partition

| File | Lines | `@test` count |
| --- | --- | --- |
| `tests/push_behind_vs_diverged.bats` | 294 | 8 |
| `tests/push_tier_publication.bats` | 250 | 7 |
| `tests/push_tier_publication_failures.bats` | 177 | 6 |
| `tests/helpers/push-fixtures.bash` (helper, not a `.bats` file) | 118 | — |

Total 21 `@test` blocks, matching the original's `grep -c '^@test' tests/push_behind_vs_diverged.bats` = 21.

Partition matches the dispatch exactly, split at the named banners:

- `tests/push_behind_vs_diverged.bats`: everything up to (not including) the banner "a repair the take makes inside a push publishes before memory records it" — preparation, remote-flavor, tier-loop, local-flavor, tier-direction sections.
- `tests/push_tier_publication.bats`: that banner through (not including) "a behind arm's own repair must survive a later tier's failure" — in-push repair publication, the behind arm's retry wording, and the mid-loop repair-to-a-different-tier sections with `install_tier_live_snapshot_hook`, `advance_tier_past_remote`, `push_side_ref_child`, `move_tier_remote_live_on_next_push`, `setup_repair_race_on_aa`, `assert_aa_live_repairs`, `assert_aa_repaired_mid_loop`.
- `tests/push_tier_publication_failures.bats`: that banner to the end — `decline_tier_pushes_recording`, the surviving-repair test, the post-loop wording tests, `decline_tier_pushes_after_first`.

No deviation from the proposed partition.

## Helper file contents (`tests/helpers/push-fixtures.bash`)

One line per moved item, all moved verbatim from the original:

- `CMD="$PLUGIN_ROOT/scripts/push-memory.sh"` (with the `# shellcheck disable=SC2034` comment above it, matching `merge-memory.bash`'s convention for this same shape) — used by all three files.
- `setup()` — `setup_tmp_repo`, exports `CLAUDE_PLUGIN_ROOT`, sets and exports `MEMORY_REMOTE` — used by all three files (each relies on the loaded definition; none redeclares it).
- `teardown()` — `teardown_tmp_repo` — used by all three files.
- `publish_memory()` — wires `origin` on `memory` to `$MEMORY_REMOTE`, pushes `live`, sets `gitlore.hooksDir` — called directly in files 1, 2 and 3, and from `wire_memory_remote` (file 1) and `setup_repair_race_on_aa` (this helper file).
- `mount_tier_at_live()` — mounts a tier and detaches its worktree at `live` — called directly in all three files.
- `advance_tier_past_remote()` — commits a plain change to a tier past its remote — called directly in file 3 (`decline_tier_pushes_recording`'s test) and from `setup_repair_race_on_aa` (this file).
- `push_side_ref_child()` — builds a side-ref child commit on a tier's bare remote — called only from `setup_repair_race_on_aa`; moved alongside it since that is its only caller.
- `move_tier_remote_live_on_next_push()` — one-shot post-receive hook that snaps a tier remote's `live` — called only from `setup_repair_race_on_aa`; moved alongside it for the same reason.
- `setup_repair_race_on_aa()` — builds the two-tier repair-race fixture, sets `$P`/`$D` — called from file 2's two mid-loop tests and file 3's two post-loop tests.
- `assert_aa_live_repairs()` — asserts `aa`'s local `live` repairs a given parent, sets `$aa_live` — called from `assert_aa_repaired_mid_loop` (file 2, below) and directly from three tests in file 3.

Helpers used by exactly one resulting file stayed in that file, above their first user, unchanged:

- `wire_memory_remote`, `advance_memory_remote`, `add_memory_commit` — file 1 only.
- `install_tier_live_snapshot_hook` — file 2 only (three call sites, all within file 2's range).
- `assert_aa_repaired_mid_loop` — file 2 only (calls the now-shared `assert_aa_live_repairs`, which resolves fine since `helpers/push-fixtures` is loaded first).
- `decline_tier_pushes_recording`, `decline_tier_pushes_after_first` — file 3 only.

## Deviations from the proposed partition

None. The line ranges given in the dispatch matched the actual banner positions once re-measured against the file read at the start of this task (banners at 320, 511 comment-adjacent 512/513 boundary, 644, and the actual close of the file at 806); the only refinement needed was locating the exact blank-line boundaries around the helper functions being extracted, which the diff-based verification below confirms did not drop or duplicate any line.

## Headers

Each new file repeats the shebang, the `# shellcheck disable=SC2154` line (all three files use `run --separate-stderr` and `$stderr`), `bats_require_minimum_version 1.5.0` (all three use `run --separate-stderr`), and the four `load` lines (`helpers/setup`, `helpers/fixtures`, `helpers/tier-fixtures`, `helpers/push-fixtures`).

The original's header comment (lines 2–15) is entirely about the behind-vs-diverged discriminator and the HEAD/`live` invariant; no sentence in it describes only the publication sections, so nothing needed to move out of it — it stays whole in `tests/push_behind_vs_diverged.bats`. `tests/push_tier_publication.bats` and `tests/push_tier_publication_failures.bats` each got a fresh 3-line opening comment (written for this split, not present in the original) describing what that file covers.

## References swept

Sweep command run exactly as specified:
`grep -rn 'push_behind_vs_diverged\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md` — no hits.

Also checked bare `push_behind_vs_diverged` (no `.bats` suffix) and the `justfile`, `scripts/run-bats.sh`, `tests/justfile_gates.bats`, `tests/plugin_distribution.bats`, `docs/references/testing.md` individually — no suite enumeration by name anywhere in that set; none of these files name bats suites individually (they use directory globs).

A broader repo-wide grep (outside the mandated sweep paths) turned up two categories of hits, both excluded from this sweep by the brief's own scope, and left alone:

- `.claude/handoff-todo.md:3` — excluded per the brief's explicit `.claude/` exclusion.
- ~90 hits under `plans/**/reports/*.md` and a few `plans/**/{outline,runbook,recall-artifact}.md` — these are frozen historical job reports and plans from already-completed work (e.g. `plans/tier-arrival-review-minors/`, `plans/unadoptable-tier-arrival/`, `plans/2026-09-18-remaining-items/`), citing line numbers and test-run counts specific to a past point in time. They are the `plans/` analogue of `docs/changelog/`, which the brief explicitly excludes — repointing them would misrepresent history rather than correct a live reference. None of them describes present-tense "this test lives in file X" routing that a reader would follow today; they are records of what was true when each job ran.

No comment, doc, or memory-free text pointed a MOVED test or section at the original file in a way needing repointing — the sweep found nothing in the in-scope paths at all.

## Duplicate helper note

`tests/helpers/resolve-compose.bash:18` defines a `mount_tier_at_live()` byte-identical to the one now in `tests/helpers/push-fixtures.bash` (both: `local tier="${1:-ddaanet}"`, `make_tier_in_memory`, fetch `live:live`, detached checkout). Per the brief, not deduped or merged — left as two independent definitions in two independent helper files, noted here only.

`tests/helpers/merge-memory.bash` also defines a `wire_memory_remote()`, but its body differs (it inlines the remote-wiring steps directly rather than delegating to a `publish_memory` helper) — not a duplicate.

## Verification commands and results

1. Test names preserved:
   `diff <(cat /tmp/claude-1000/push_behind_vs_diverged.orig.bats | grep '^@test' | sort) <(cat tests/push_behind_vs_diverged.bats tests/push_tier_publication.bats tests/push_tier_publication_failures.bats | grep -h '^@test' | sort)`
   → no output (clean).

2. No line lost:
   `diff <(sort /tmp/claude-1000/push_behind_vs_diverged.orig.bats) <(cat tests/push_behind_vs_diverged.bats tests/push_tier_publication.bats tests/push_tier_publication_failures.bats tests/helpers/push-fixtures.bash | sort) | grep '^<'`
   → no output (clean). No header/load/setup line needed to be listed as a deliberate replacement beyond the standard load-line and CMD/setup/teardown consolidation already described above.

3. `wc -l` of every resulting file:
   ```
   294 tests/push_behind_vs_diverged.bats
   250 tests/push_tier_publication.bats
   177 tests/push_tier_publication_failures.bats
   118 tests/helpers/push-fixtures.bash
   ```

4. `scripts/run-bats.sh tests/push_behind_vs_diverged.bats tests/push_tier_publication.bats tests/push_tier_publication_failures.bats`
   → `bats: 21 passed, 0 failed` — matches `grep -c '^@test' /tmp/claude-1000/push_behind_vs_diverged.orig.bats` = 21.

5. `just lint` (timeout 600000):
   → `lint-shell: 141 files clean`.

6. Per the brief, `just test-unit` was not run.
