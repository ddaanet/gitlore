# Item 2.2 — GREEN report

Commit: `7b8407f` — "Item 2.2/1-6 — a take repairs a defective arrival with a
plain commit in live" (subject rewritten with emoji by the commit-msg hook).
Files: `scripts/lib/resolve.sh`, `tests/merge_memory.bats` (test file untouched
by this dispatch — its content was already staged from the RED/test-review work;
only `resolve.sh` was edited here).

## What changed

`gitlore_adopt_tier_into_root` grew a repair arm: when the up projection refuses
(rc 1) and `gitlore_compose_problems_in` finds a problem naming the arriving
carrier, it calls a new `gitlore_adopt_repair_arrival` instead of printing the
first refusal and walking back. That function copies the arrival's and the pin's
carriers into scratch files under the tier's absolute gitdir, runs
`gitlore_repair_index`, rechecks the repaired copy, builds R from a temporary
index (`read-tree HEAD`, `hash-object -w`, `update-index --cacheinfo`,
`write-tree`, `commit-tree -p HEAD`), advances the tier's local `live` to R,
checks it out, prints the report lines, and retries `gitlore_compose_up`. Three
small helpers were factored out for reuse across the success and failure paths:
`gitlore_adopt_walk_back_tier` (return to the pin),
`gitlore_adopt_report_refusal_and_walk_back` (today's refusal header +
walk-back, shared by the no-repair arm and a failed retry), and
`gitlore_adopt_stage_pair_and_commit` (the landed-take tail, shared by a plain
take and a landed repair).

Every helper call whose failure the caller intentionally ignores (because it
always returns 1, or because the caller returns 1 regardless) is guarded with
`|| :` before the following `return 1` — verified against bash 5.2 that an
unguarded failing statement mid-function does NOT abort under `set -e` when the
enclosing call is itself invoked via `||` (the exemption is transitive into a
function's body), but the fix does not rely on that: it matches the file's own
explicit-guard idiom, which is what stays correct regardless of bash version
differences (macOS ships 3.2).

## Order tests went green

Each slice was run individually via `--filter` against the already-red test
before moving to the next; no test needed a second implementation attempt.

1. "a take repairs a duplicate pointer that arrived and adopts the repair"
   (slice 1, external contract)
2. "a take repairs a welded line that arrived" (slice 2, guard)
3. "a take repairs an interleaved non-bullet line that arrived" (slice 2, guard)
4. "a repair beside a root problem lands in live and waits" (slice 3)
5. "an arrival the repair cannot fix walks back and names upstream" (slice 4)
6. "a local live that ran ahead with a defective carrier is repaired" (slice 5,
   guard)
7. "a refused live update after the repair leaves no trace" (slice 6)

## Suite results

- `scripts/run-bats.sh tests/merge_memory.bats` (whole file):
  **30 passed, 0 failed**.
- `scripts/run-bats.sh tests/tier_divergence.bats`: **19 passed, 0 failed**.
- `scripts/run-bats.sh tests/push_behind_vs_diverged.bats`:
  **12 passed, 0 failed**.
- `scripts/run-bats.sh tests/resolve_compose.bats`: **9 passed, 0 failed**.
- `scripts/run-bats.sh tests/commit_memory.bats`: **35 passed, 0 failed**.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats`: clean, no output.

## Notes

- Scope held: only `gitlore_adopt_tier_into_root` and its new helpers changed in
  `resolve.sh`; `gitlore_merge_one_store`'s fetch order and
  `gitlore_push_stores`' `behind` arm (Item 2.3) and `scripts/resolve.sh` (Items
  3.1, 4.1) were not touched.
- No test was weakened or edited.
