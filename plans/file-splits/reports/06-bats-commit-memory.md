# Split report — tests/commit_memory.bats

Followed `plans/file-splits/brief-bats.md`. Split target was the WORKING TREE
copy of `tests/commit_memory.bats` (1056 lines, carrying earlier reviewed
comment edits), snapshotted to `$TMPDIR/commit_memory.orig.bats` before
editing and used in place of `git show HEAD:...` throughout.

## Final partition

- `tests/commit_memory.bats` — 329 lines, 16 tests. The basics and the
  index-abort arm: "exits 0 when gitlore is not configured" through "a root
  index whose status cannot be read aborts the commit and says which index".
- `tests/commit_memory_reports.bats` — 266 lines, 7 tests. "a carrier defect
  in a clean tier commits and reports" through "the pin-abort's ahead wording
  reaches both the agent arm and the user arm", including the single-file
  helper `committed_carrier_defect_store()`.
- `tests/commit_memory_retry.bats` — 228 lines, 8 tests. "a commit that
  landed a tier and then failed on memory's index retries to completion"
  through "a landing record does not adopt a foreign commit stacked on the
  landed one".
- `tests/commit_memory_compose_status.bats` — 246 lines, 7 tests. "a manifest
  refusal is reported and does not abort the commit" through "the pin-abort
  user arm tells a user to retry".
- `tests/helpers/commit-memory.bash` — 33 lines (new file). Shared setup and
  the cross-file driver helper.

16+7+8+7 = 38 tests, matching `grep -c '^@test' $TMPDIR/commit_memory.orig.bats`.

## Helper file contents

`tests/helpers/commit-memory.bash`, loaded by all four `.bats` files with
`load helpers/commit-memory`:
- `CMD` — the file-level path to `commit-memory.sh`, moved verbatim (with a
  `# shellcheck disable=SC2034 # used by callers' @test bodies` line added,
  the pattern already used in `tests/helpers/merge-memory.bash` and
  `tests/helpers/index-sync.bash`, since shellcheck can no longer see the
  in-file use).
- `setup()` / `teardown()` — moved verbatim (multi-line, used by every file).
- `write_sync_driver()` — moved verbatim except its doc comment (see below).
  Used in `tests/commit_memory.bats` (the two rc-1 status-read-failure tests)
  and `tests/commit_memory_retry.bats` (four call sites) — used by more than
  one resulting file, so it moved per the brief's rule rather than staying in
  `commit_memory_retry.bats` where its old file position (line 811, after
  every one of its callers) sat.

`committed_carrier_defect_store()` is used only by two tests inside
`tests/commit_memory_reports.bats` (both call sites), so it stayed local
there, in its original position after both callers — order inside the file
otherwise follows the original.

## Deviations from the proposed partition

- The dispatch's proposed cut points matched exactly; the only adjustment was
  moving `write_sync_driver()` out of the fourth file's chunk (where it lived
  in the original, at line 811, immediately before "a manifest refusal is
  reported and does not abort the commit") and into the new helper file,
  because two other resulting files call it. `committed_carrier_defect_store`
  needed no such move since only one resulting file uses it.
- The `gitlore_compose() {` line the dispatch flagged near the original's line
  945 is confirmed to be inside a heredoc in the body of "an unrecognised
  compose status aborts and keeps the approval" (now in
  `tests/commit_memory_compose_status.bats`), not a file-level helper — it
  moved verbatim as part of that test.

## Headers

Every resulting file repeats: shebang, the `# shellcheck disable=SC2154`
line (every file still uses `$stderr` from `run --separate-stderr`, so it is
needed everywhere), `bats_require_minimum_version 1.5.0` (every file still
uses `run --separate-stderr`), the `load` lines it needs, and a 1–3 line
comment on what the file covers. `# shellcheck disable=SC2030,SC2031` (the
spaced-root re-root disable) is needed only in `tests/commit_memory_retry.bats`
— the one file containing "a half-landed tier commit retries to completion
under a project path holding a space", the sole test in the whole original
file that reassigns `$TMP_REPO` — so it dropped from the other three files.
Its accompanying comment changed from "The spaced-root cases re-root..." to
"The spaced-root case re-roots..." (plural → singular), per the brief's
explicit license for a comment whose plural/singular wording stops being
accurate for the file it lands in.

`load helpers/divergence-fixtures` is used only by `advance_branch_with_file`
in "exits 1 with merge directive when branch diverged from live" (now in
`tests/commit_memory.bats`), so it was dropped from the other three files'
load lists — verified by grep before writing each file.

## References

Ran the mandated sweep:
`grep -rn 'commit_memory\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`
— zero hits (the only match anywhere in that scope is the new helper file's
own header comment, which names the suite family, not a stale pointer).

Also checked `justfile`, `scripts/run-bats.sh`, `tests/justfile_gates.bats`,
`tests/plugin_distribution.bats`, `docs/references/testing.md` for suites
enumerated by name — no hits.

A broader repo grep for `commit_memory.bats` (unscoped) turns up ~70 hits, all
under `plans/` (frozen, dated plan/report documents from prior work, e.g.
`plans/index-edit-propagation/reports/*.md`, `plans/2026-09-18-remaining-items/
reports/*.md`) and one in `docs/changelog/2026-06-12-d16-standalone-memory-
commit.md`. Both are outside the brief's own grep scope (which deliberately
omits `plans/` and `docs/changelog/`) and are historical records — left
unchanged, matching the precedent in
`plans/file-splits/reports/04-bats-index-compose.md`.

## Verification

1. Test names preserved:
   `diff <(grep '^@test' "$TMPDIR/commit_memory.orig.bats" | sort) <(cat tests/commit_memory.bats tests/commit_memory_reports.bats tests/commit_memory_retry.bats tests/commit_memory_compose_status.bats | grep -h '^@test' | sort)`
   → prints nothing.

2. No line lost:
   `diff <(sort "$TMPDIR/commit_memory.orig.bats") <(cat tests/commit_memory.bats tests/commit_memory_reports.bats tests/commit_memory_retry.bats tests/commit_memory_compose_status.bats tests/helpers/commit-memory.bash | sort) | grep '^<'`
   → prints exactly 5 lines, all from the deliberately reworded/rewrapped
   `write_sync_driver()` doc comment (dropping "above", now inaccurate since
   the callers live in other files) and the spaced-root header comment
   (plural → singular, licensed above):
   ```
   < # The driver the approval cases above share: gitlore_sync_memory_to_live
   < # The spaced-root cases re-root $TMP_REPO inside their own test body.
   < # called the way the pre-commit hook calls it, on the summary file as it
   < # stand a function in for a state no fixture reaches.
   < # stands. $1 = optional shell text run after the libraries are sourced, to
   ```

3. `wc -l`:
   ```
     329 tests/commit_memory.bats
     266 tests/commit_memory_reports.bats
     228 tests/commit_memory_retry.bats
     246 tests/commit_memory_compose_status.bats
      33 tests/helpers/commit-memory.bash
   ```
   All four `.bats` files are well under the 380-line cap.

4. `scripts/run-bats.sh tests/commit_memory.bats tests/commit_memory_reports.bats tests/commit_memory_retry.bats tests/commit_memory_compose_status.bats`
   → `bats: 38 passed, 0 failed`. 38 matches
   `grep -c '^@test' "$TMPDIR/commit_memory.orig.bats"`.

5. `just lint` → `lint-shell: 141 files clean`.

6. Per the brief, `just test-unit` was not run.
