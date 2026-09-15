# Item 3.1 — test review

Scope: uncommitted changes to `tests/resolve_compose.bats`. `scripts/` read
only; left byte-identical (`cmp` against the saved copy,
`git status --porcelain -- scripts/` empty).
`shellcheck tests/resolve_compose.bats` clean after fixes.

## Fixes applied

1. **Root `MEMORY.md` byte-identity was a string compare** (`$(cat …)` strips
   trailing newlines). Both slice-1 tests now `cp` the root index to
   `$BATS_TEST_TMPDIR/root-before` and `cmp` it after the continuation.
2. **Head-vs-live flavor was only logged, never asserted.** Both slice-1 tests
   now assert `jq -r .flavor` of the tier's state file right after preparation
   (`head-vs-remote` / `head-vs-live`), so the two tests provably cover the two
   flavors.
3. **Slice 3's two-parent check was ancestry-blind.**
   `rev-list --count --merges "$merged" -1` counts the first merge *reachable*
   from `$merged`, so any ancestor merge satisfies it. Replaced with
   `rev-parse -q --verify "$merged^2"` plus `run ! … "$merged^3"`. (The same
   idiom in the pre-existing tests is out of scope and left alone.)
4. **Slices 2 and 3 hid their premise** behind `continue-after-merge || true`.
   Now `run … continue-after-merge; [ "$status" -eq 1 ]`, so on unchanged code
   they fail visibly at slice 1's refusal rather than at a downstream symptom
   (slice 3 used to fail on "no merge state file").
5. **Slice 4 captured memory HEAD before the preparing pre-commit.** The
   memory-root head-vs-live preparation moves memory HEAD, so under a correct
   implementation both slice-4 tests failed on `HEAD = $mem_before` (found by
   the sketch run). `mem_before` is now read after `bash "$PRE_COMMIT"`.
6. **Citations in test source:** removed "K4's trigger" from the
   `duplicate_tier_carrier` comment and the `tests/tier_divergence.bats:143`
   line number from `prepare_tier_merge_head_vs_live`'s (now names the
   pre-commit preparation in tier_divergence.bats).
7. State-file paths use `gitlore_merge_state_file memory/ddaanet`, matching the
   memory-root tests (returns an absolute path; verified).

## Checks

- **Sketch of the runbook change** in `compose_merged_indexes` (after
  `gitlore_compose_up`, on rc 1 filter the problems through
  `gitlore_compose_problems_in` for `$memroot/$merged_tier/MEMORY.md` or
  `$memroot/MEMORY.md`; on a match print the header and lines and `exit 1`),
  saved original under a checked `mktemp -d`: whole file 15/15 green after fix 5
  (first run 13/15, the two failures being fix 5). Includes slice 5 and the
  unchanged "a tier merge the root index cannot adopt lands, records nothing in
  the root, and is adopted by the next take" (the passing carrier beside a
  root-only `gone/x.md` problem).
- **Mutation, slice 2** (refusal also clears the state file and `MERGE_HEAD`):
  red at `[[ "$stderr" == *"continue-after-merge"* ]]`.
- **Mutation, slice 3** (refusal leaves a marker that refuses every later
  continuation): red at the second continuation's `[ "$status" -eq 0 ]`.
- **Mutation, slice 5** (sketch blocks any memory-root rc 1 regardless of
  attribution): red at `[ "$status" -eq 0 ]`. Complements the RED report's
  mutation of today's code.
- **Slice 4 fixtures:** under the sketch, stderr carries
  `memory/MEMORY.md: duplicate pointer path p.md` and
  `memory/MEMORY.md: line … welds two pointer bullets`, so both refusals are
  attributed to the root index. The rewrite asserts nothing the old test did (no
  "composition refused", no landed merge, no cleared state file).
- **Slice 5 attribution:** the leftover-prefix problem line
  (`root index line 'gone/x.md' has a prefix naming no mounted tier …`) has no
  `memory/MEMORY.md: ` prefix, so the guard really separates the two arms.
- Assertions match the runbook: `was not committed`,
  `memory/ddaanet/MEMORY.md: duplicate pointer path t.md`, state file and
  `MERGE_HEAD` present, tier HEAD pre-merge, root `cmp`, memory HEAD unchanged;
  slice 3 two-parent merge, `HEAD:ddaanet` is it, prefixed root line.
- Bats pitfalls: no bare `! cmd`; every stderr assertion follows
  `run --separate-stderr`; no multi-line grep. No test holds a ref or index
  lock, so `GITLORE_GIT_RETRY_SCHEDULE=0` is not needed. Paths are quoted.

## Final red pattern (unchanged scripts)

`scripts/run-bats.sh tests/resolve_compose.bats`: 9 passed, 6 failed — each
failing at `[ "$status" -eq 1 ]`: slice 1 ×2 (lines 170, 189, after the flavor
assertions pass), slices 2 and 3 at the first continuation's refusal (203, 214),
slice 4 ×2 (344, 362). Slice 5 and all pre-existing tests green.

No UNFIXABLE issues.
