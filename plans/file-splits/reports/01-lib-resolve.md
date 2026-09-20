# Split scripts/lib/resolve.sh

`scripts/lib/resolve.sh` was 2327 lines. Split by pure moves — comment block
plus function, verbatim — into eight sibling `resolve-*.sh` files, each
function-only and safe to source twice, sourced from `resolve.sh` after its
existing two `source` lines. Every caller (`scripts/push-memory.sh`,
`merge-memory.sh`, `commit-memory.sh`, `resolve.sh`, `git-hooks/pre-push`,
`git-hooks/pre-commit`, `cc-hooks/session-start.sh`, and the bats files that
source it) still sources only `scripts/lib/resolve.sh`, unchanged.

## Final partition (line counts, `wc -l`)

| File | Lines | Holds |
|---|---|---|
| `scripts/lib/resolve.sh` | 307 | source lines + `gitlore_memory_stores`, `gitlore_stores_with_merge_state`, `gitlore_detect_stale_merge_state`, `gitlore_guard_stale_merge_state`, `gitlore_classify_refusal`, `gitlore_check_head_live_agree`, `gitlore_store_repo_name`, `gitlore_consumer_name`, `gitlore_merge_commit_message` |
| `scripts/lib/resolve-recovery.sh` | 343 | `gitlore_recover_stale_no_merge_head` … `gitlore_drop_merge_preparation` |
| `scripts/lib/resolve-merge-state.sh` | 360 | `gitlore_write_merge_marker` … `gitlore_yield_merge` |
| `scripts/lib/resolve-sync-tiers.sh` | 109 | `gitlore_sync_tiers_to_live` |
| `scripts/lib/resolve-sync-memory.sh` | 290 | `gitlore_sync_memory_to_live` |
| `scripts/lib/resolve-push.sh` | 343 | `gitlore_say_unreadable_index_status`, `gitlore_stage_landed_tiers`, `gitlore_push_stores`, `gitlore_report_tier_push_failure` |
| `scripts/lib/resolve-merge-stores.sh` | 246 | `gitlore_merge_stores`, `gitlore_merge_one_store`, `gitlore_repair_stranded_live`, `gitlore_live_ahead_of_head` |
| `scripts/lib/resolve-adopt.sh` | 235 | `gitlore_adopt_advanced_live`, `gitlore_adopt_tier_into_root`, `gitlore_adopt_repair_arrival`, `gitlore_adopt_commit_repair` |
| `scripts/lib/resolve-adopt-report.sh` | 165 | `gitlore_adopt_report_refusal_and_walk_back`, `gitlore_adopt_print_root_refusal`, `gitlore_adopt_walk_back_tier`, `gitlore_adopt_stage_pair_and_commit`, `gitlore_commit_tier_bookkeeping`, `gitlore_root_dirty_beyond_pair` |

All nine files end at or under 360 lines, within the 380 cap. Mode bits
match the existing lib files (644).

## Deviation from the proposed partition

The task's proposed `resolve-sync-live.sh` (`gitlore_sync_tiers_to_live` +
`gitlore_sync_memory_to_live`, 939–1311) is 390 content lines before any
header — over the 380 cap on its own. Split it at the function boundary into
`resolve-sync-tiers.sh` (the tier loop) and `resolve-sync-memory.sh` (the
FR11 commit path, the larger of the two at 285 content lines). These are
already two independently-named functions with a clear boundary (the tier
loop is called from inside the memory-sync function), so no function was
cut.

Likewise the proposed `resolve-adopt.sh` (1910–2278) is 390 content lines
before any header. Split at `gitlore_adopt_repair_arrival` /
`gitlore_adopt_commit_repair` vs. the reporting/walk-back/bookkeeping tail:
`resolve-adopt.sh` keeps the adoption and carrier-repair logic
(`gitlore_adopt_advanced_live`, `gitlore_adopt_tier_into_root`,
`gitlore_adopt_repair_arrival`, `gitlore_adopt_commit_repair`);
`resolve-adopt-report.sh` keeps the refusal-reporting, walk-back, and
landed-commit tail (`gitlore_adopt_report_refusal_and_walk_back`,
`gitlore_adopt_print_root_refusal`, `gitlore_adopt_walk_back_tier`,
`gitlore_adopt_stage_pair_and_commit`, `gitlore_commit_tier_bookkeeping`,
`gitlore_root_dirty_beyond_pair`). Eight part files ship instead of the
proposed seven.

Every other group (recovery, merge-state, push, merge-stores, and the three
chunks that stay in `resolve.sh` itself) matched the proposed line ranges
and needed no further split.

## References updated

- `scripts/lib/resolve.sh:10-24` — extended the header comment with a
  present-tense paragraph naming each `resolve-*.sh` part and its purpose,
  ahead of the eight new `source` lines.
- `tests/killed_take_repro.bats:11` — `scripts/lib/resolve.sh` →
  `scripts/lib/resolve-adopt.sh` (names `gitlore_adopt_advanced_live` and
  `gitlore_adopt_tier_into_root`, both moved there).
- `tests/killed_take_repro.bats:99` — `scripts/lib/resolve.sh` →
  `scripts/lib/resolve-adopt-report.sh` (names
  `gitlore_adopt_stage_pair_and_commit`, moved there).
- `tests/push_rejection_discriminator.bats:8` — the top-comment site list's
  `scripts/lib/resolve.sh push . HEAD:live (head-vs-live)` →
  `scripts/lib/resolve-sync-memory.sh push . HEAD:live (head-vs-live)`
  (`gitlore_sync_memory_to_live`'s own discriminator moved there).
- `tests/push_rejection_discriminator.bats:263` — the "already covered
  here" comment's `gitlore_push_stores in scripts/lib/resolve.sh` →
  `scripts/lib/resolve-push.sh` (where `gitlore_push_stores` now lives).
- `tests/push_rejection_discriminator.bats:268-270` — the `for site in`
  loop, which greps each named file directly for the pinned rejection
  pattern, changed from `scripts/lib/resolve.sh` / `scripts/resolve.sh` to
  `scripts/lib/resolve-sync-memory.sh` / `scripts/lib/resolve-push.sh` /
  `scripts/resolve.sh` — both new lib files independently contain the
  pattern now, so both needed to be in the loop for the "already covered"
  comment's claim to hold. This is a functional fix, not a comment-only
  update: the grep against the unmodified `scripts/lib/resolve.sh` path
  alone would have found no match and failed the test.

Left alone (mean the library as a whole, not a specific moved function, so
per instructions not repointed): `scripts/lib/util.sh:106`,
`docs/references/commit-gate.md` (several `resolve.sh` / `(lib)`
mentions), `docs/references/memory-entry-points.md`,
`docs/references/git-hooks.md`, `docs/references/tier-stores.md`,
`docs/references/merge-state-recovery.md`,
`docs/references/merge-and-resolve.md`, `skills/resolve/SKILL.md`,
`agents/memory-merger.md` (all name `scripts/resolve.sh`, the top-level
driver script, which is untouched, or a `gitlore_*` function name with no
file-path attribution to update). `docs/changelog/` untouched per
instructions (history). `.claude/handoff-todo.md` names this split as
future work but is tooling-managed — left for the handoff skill.
`tests/plugin_distribution.bats`, `scripts/lint-shell.sh`, and `justfile`
enumerate no lib files needing the new names, confirming the brief's
expectation.

## Verification

1. **Function-set equivalence** (adapted from the brief's one-liner — the
   original used a `sed`-based BASH_SOURCE rewrite meant for a file moved
   into a different directory, which doesn't apply here since every new
   part is a plain sibling `source`; the check below instead sources the
   real `resolve.sh` from its real location, both before and after, and
   diffs the full `declare -f` output of every `gitlore_` function):

   ```
   git show HEAD:scripts/lib/resolve.sh > "$TMPDIR/resolve-old.sh" \
     && diff \
       <(bash -c 'cd scripts/lib && source ./util.sh && source ./log.sh \
           && sed "s#\${BASH_SOURCE\[0\]%/\*}#.#" "$0" > "$0.patched" \
           && source "$0.patched" \
           && declare -f $(declare -F | awk "{print \$3}" | grep "^gitlore_")' \
         "$TMPDIR/resolve-old.sh") \
       <(bash -c 'cd scripts/lib && source ./util.sh && source ./log.sh \
           && source ./resolve.sh \
           && declare -f $(declare -F | awk "{print \$3}" | grep "^gitlore_")')
   ```

   Output: empty. Exit code 0. Every `gitlore_` function's body is
   byte-identical before and after the split.

2. **Comment preservation**:
   - old: `git show HEAD:scripts/lib/resolve.sh | grep -c '^ *#'` → **1065**
   - new: `grep -c '^ *#' scripts/lib/resolve.sh scripts/lib/resolve-recovery.sh
     scripts/lib/resolve-merge-state.sh scripts/lib/resolve-sync-tiers.sh
     scripts/lib/resolve-sync-memory.sh scripts/lib/resolve-push.sh
     scripts/lib/resolve-merge-stores.sh scripts/lib/resolve-adopt.sh
     scripts/lib/resolve-adopt-report.sh`, summed → **1128**

   Delta of 63 lines, entirely the new header comment paragraph in
   `resolve.sh` (naming each part) and the eight new part-file headers
   (shebang-adjacent 4-5 line "what this holds / source that, not this
   file" comments) — no function comment was shaved or joined.

3. **Line counts** (`wc -l scripts/lib/resolve.sh scripts/lib/resolve-*.sh`):
   307, 343, 360, 246, 235, 165, 343, 109, 290 — all ≤ 380 (see table
   above for the file-to-count mapping).

4. **`just lint`**: `lint-shell: 141 files clean`.

5. **`just test-unit`**: `bats: 976 passed, 0 failed`.
   **`just test-integration`**: `bats: 72 passed, 0 failed`.
   Both run in the foreground per instructions; the first foreground
   attempt exceeded the tool's 600s wait and was moved to background by
   the harness, but its own run continued and completed normally (exit 0,
   976/0) — confirmed by the gate file `test-unit`'s hash and a fresh
   mtime after the two `tests/push_rejection_discriminator.bats` /
   `tests/killed_take_repro.bats` edits. `test-integration` completed
   within the foreground wait on the first try.
