# Item 1.3, slice 1 — test review

Reviewed: the new cases in `tests/resolve_recovery.bats` and the shared helper
`tier_prepare_head_vs_live`, against
`plans/index-edit-propagation/reports/item-1-3-s1-red.md`.

Verdict: the RED report is accurate. Four cases red on the assertions it names,
case 3 is green, and case 3 is a genuine regression pin — it reds under the
naive staging. Three fixes applied to the tests, one of them a new born-green
case 6 pinning the memory-root exclusion that the §4 finding uncovered and main
accepted.

`git diff scripts/` is **empty**; `scripts/lib/resolve.sh` is byte-identical to
HEAD (`git diff --exit-code scripts/` returns 0). Nothing staged, nothing
committed. No `just` recipe was run.

## 1. Mechanical check — unchanged code

`scripts/run-bats.sh --jobs 1 tests/resolve_recovery.bats` —
`16 passed, 4 failed`. The twelve pre-existing cases all pass. Line numbers are
the file as it stands after the fixes in §3.

| # | case | result | failing assertion |
| --- | --- | --- | --- |
| 13 | 1 — a landed tier merge stages the moved gitlink | FAILED | `:367` `[ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]` |
| 14 | 2 — the HEAD-already-carries branch stages it too | FAILED | `:387` same pin equality |
| 15 | 3 — the memory root stages nothing in the parent repo | PASSED (born-green, by decision) | — |
| 16 | 4 — the memory commit runs to completion | FAILED | `:440` `[ "$status" -eq 0 ]` |
| 17 | 5 — a staging failure is reported, rc stays 0 | FAILED | `:461` `[[ "$stderr" == *"could not be staged"* ]]` |
| 18 | 6 — a host project keeping a root `MEMORY.md` is not a memory store | PASSED (born-green, added by this review) | — |

No case ERRORed: every failure is a failed assertion inside the test body, none
is a missing helper, a fixture abort or a non-zero exit from
`tier_prepare_head_vs_live`.

**Case 4 reds for the reason claimed, verified rather than argued.** I captured
the second `pre-commit` run's stderr from inside the case. It is, verbatim:

```
gitlore: the merge in <tmp>/memory/ddaanet landed as f2becdf6… before a checkout or reset moved HEAD off it; HEAD is restored to it and the leftover merge state cleared, so none of that merge is lost.
gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
tier 'ddaanet' is checked out at f2becdf62803 but the memory store records f1cf321e0139: it was moved outside /gitlore:merge, …
```

That is `gitlore_recover_landed_merge` restoring HEAD and Item 1.2's pin guard
then aborting on the tier gitlore itself just moved — the exact defect the slice
exists to close, not an unrelated hook failure. It also settles the
vacuous-negative worry: the guard *did* inspect the tier, so
`set_tier_manifest ddaanet` in the helper is doing its job.

**Assertions below each death point.** Cases 1 and 2 fail on their last
assertion — nothing below. Case 5 likewise (`:461` is last). Case 4 fails at
`:440`, so `:441` (`":ddaanet" = "$landed"`) never executes against unchanged
code; it is proven by the BASE3 run in §2, where it executes and holds. Case 1's
new `:373` assertion sits below the death point for the same reason and is
proven the same way (BASE3 green, M2f red).

## 2. Mutation matrix

All mutations were applied in place to `scripts/lib/resolve.sh` and reverted.

**BASE3** is the staging implementation slice 1's GREEN should write under the
corrected spec: a `gitlore_stage_recovered_gitlink "$store" "$abs" "$landed"`
helper called from both rc-0 branches, guarded by three clauses —

1. the superproject carries a root `MEMORY.md`;
2. the store's path relative to it is in `gitlore_tier_paths "$super"`;
3. that path is **not** the superproject's own
   `git config --file "$super/.gitmodules" submodule.gitlore-memory.path`

— staging with `gitlore_git -C "$super" add -- "$rel"` and reporting a failure
on stderr with the `gitlore_adopt_tier_into_root` wording.

The matrix is stated against BASE3, so the mutation names differ from the ones
in the interim report main has already read: what was `M1b` there (the
one-clause `MEMORY.md`-only predicate) reds case 6 and is now covered by
**M1c**, which isolates the same defect by removing exactly the clause at issue.

| mutation | c1 (13) | c2 (14) | c3 (15) | c4 (16) | c5 (17) | c6 (18) |
| --- | --- | --- | --- | --- | --- | --- |
| BASE3 — the corrected three-clause implementation | green | green | green | green | green | green |
| M1 — naive: stage whenever `--show-superproject-working-tree` is non-empty, no clauses | green | green | **RED** `:423` | green | green | **RED** `:511` |
| M1a — drop clause 1 (`MEMORY.md`) | green | green | green | green | green | green |
| M1b — drop clause 2 (`gitlore_tier_paths`) | green | green | green | green | green | green |
| M1c — drop clause 3 (the memory-root exclusion) = the pre-correction two-condition spec | green | green | green | green | green | **RED** `:511` |
| M3 — clause 3 via cwd-relative `gitlore_memory_path` instead of `git config --file "$super/.gitmodules"` | green | green | green | green | green | **RED** `:511` |
| M2a — wrong sha: `update-index --cacheinfo` the stale pin instead of `add` | **RED** `:367` | **RED** `:387` | green | **RED** `:440` | green | green |
| M2b — wrong repo: stage into the superproject's own superproject | **RED** `:367` | **RED** `:387` | green | **RED** `:440` | **RED** `:461` | green |
| M2c — fire only on the HEAD-moves branch, not the HEAD-already-carries branch | green | **RED** `:387` | green | green | green | green |
| M2d — staging failure made silent (`>/dev/null 2>&1 \|\| :`) | green | green | green | green | **RED** `:461` | green |
| M2e — ordering: stage before HEAD is restored to the merge | **RED** `:367` | green | green | **RED** `:440` | green | green |
| M2f — over-broad: `add -A` in the superproject instead of `add -- "$rel"` | **RED** `:373` | green | green | green | green | green |

Readings:

- **M1 is the proof case 3 owed, and it holds.** Case 3 reds under the naive
  staging, so it discriminates and is a real regression pin. Do not touch it.
- **M1c is case 6's proof and isolates one clause.** Only case 6 moves, so case
  6 is what defends the memory-root exclusion; every other case is indifferent
  to it.
- **M3 shows the cwd detail is pinned.** Case 6 calls the guard from a cwd
  outside the superproject, so a GREEN reaching for `gitlore_memory_path` (which
  reads `.gitmodules` from the current directory) reds instead of passing by
  accident.
- **Branch coverage is complete.** M2c reds case 2 alone, so case 2 is the sole
  pin on the HEAD-already-carries branch; cases 1, 4 and 5 cover the HEAD-moves
  branch.
- **M2d reds case 5 alone** — the report channel is pinned in exactly one place,
  and on stderr specifically (`--separate-stderr`), so a message emitted on
  stdout would still red.
- **M2b reds case 5 as well as 1/2/4**: with staging redirected to the user's
  project, memory's `index.lock` no longer blocks anything, so the failure
  report disappears. Expected, and it confirms case 5's induction is aimed at
  memory's index and not at something incidental.
- **M2e (ordering) is invisible to case 2** because that case's HEAD *is* the
  landed merge, so a pre-checkout `add` records the right sha anyway. Inherent
  to the branch, not a test defect; cases 1 and 4 cover it.
- **M2f was a real gap and is now closed** — see §3.
- **M1a and M1b both ship green** — see the coverage note in §4.

## 3. Fixes applied

All in `tests/resolve_recovery.bats`. `shellcheck tests/resolve_recovery.bats`
is clean after them.

1. **(critical) New case 6 — a host project that keeps a root `MEMORY.md` is not
   a memory store.** Born-green, labelled as such in the file, sitting after
   case
   5. It is case 3's fixture plus one line (`printf '# host project notes\n' >
   MEMORY.md` in the parent working tree) and asserts the parent index is untouched by the recovery. Two details are deliberate and carried in the case's comment: the mutation that isolates it is named (drop the memory-root exclusion clause — M1c — or equivalently the pre-correction two-condition predicate), and the guard is invoked from `$BATS_TEST_TMPDIR` rather than the superproject, so a GREEN using cwd-relative `gitlore_memory_path` reds (M3) instead of passing by accident. No cleanup line: the file goes with the whole tree in `teardown_tmp_repo`'s `rm -rf "$TMP_REPO"`,
   so nothing can trip errexit whatever a fixed implementation does with it.
   Verified: green against unchanged code and against BASE3, red under M1c and
   M3.

2. **(major) Case 1 gains a negative: only the gitlink is staged.** M2f — a
   GREEN that writes `gitlore_git -C "$super" add -A` instead of `add -- "$rel"`
   — passed every case unchallenged. That implementation sweeps every unapproved
   edit sitting in the memory worktree into memory's index, where the next
   approved memory commit carries it; the precedent this item is modelled on
   (`gitlore_adopt_tier_into_root`, `scripts/lib/resolve.sh:1601`) stages a
   named pair for exactly that reason. The case now writes `memory/SCRATCH.md`
   before the recovery runs and asserts, after the pin equality, that it is not
   in memory's staged list. Placed after the pin assertion deliberately, so the
   case still reds on the pin against unchanged code. Verified: BASE3 green, M2f
   red at `:373`.

3. **(minor) Case 5 uses `rev-parse --absolute-git-dir`.** It wrote the stray
   `index.lock` at `$(git -C memory rev-parse --git-dir)/index.lock` from a cwd
   of the parent repo. That path is absolute for a submodule on the git here, so
   the induction works — but the plain form is documented as resolved against
   the repo, and `gitlore_restore_staged_merge` (`scripts/lib/resolve.sh:288`)
   already uses `--absolute-git-dir` for the same reason. A relative result
   would have put the lock on the *parent's* index and turned case 5 into a
   permanent red, so the failure mode was loud rather than silent; the fix
   removes the dependency on that detail.

Checked and found sound, no change needed:

- Case 5's cleanup is `rm -f "$mem_gitdir/index.lock"`, which cannot trip
  errexit on a lock a fixed implementation removed — the conditional-restore
  trap does not apply.
- No `jq -r` in the new cases, so the literal-`null` refutation trap does not
  apply.
- No `grep -F` with a leading `---`; the text assertions are bash `[[ == * ]]`.
- bash 3.2 / BSD: the new cases use `printf`, `[[ ]]` pattern match, `rm -f`,
  `cd` and plain `git`; nothing shadowed by `tests/helpers/bsd-stubs.bash`, no
  `find`, no `sed -i`, no `mktemp` template.
- `tier_prepare_head_vs_live` asserts both that the `pre-commit` run refused
  (`[ "$status" -ne 0 ]`) and that `MERGE_HEAD` exists, so a fixture that failed
  to prepare a merge dies in the helper with a helper line number rather than
  producing a vacuous pass downstream.
- The file-level `# shellcheck disable=SC2030,SC2031` matches the precedent in
  `tests/tier_discovery.bats` and `tests/add_tier.bats`.

## 4. The predicate finding — accepted, pinned, with one residual

The finding as reported and accepted: the two-condition predicate does not
exclude what the item said it excluded. `gitlore_tier_paths`
(`scripts/lib/util.sh:360`) prints every submodule path a repo registers, with
no notion of a tier beyond enclosure, so the memory store satisfies the
tier-membership condition inside its own host; a host that keeps a root
`MEMORY.md` satisfies the other; and the recovery stages the memory gitlink into
the user's own project index, outside every approval gate. The discriminator is
the third clause — the store's path must not be the superproject's own
`submodule.gitlore-memory.path`, read with
`git config --file "$super/.gitmodules"` because `gitlore_memory_path` reads the
*current directory*'s `.gitmodules`.

That is now case 6, and BASE3 (the three-clause implementation) passes all
twenty cases, so the corrected spec is satisfiable exactly as written.

**Residual, for main rather than for GREEN — clauses 1 and 2 are unpinned.** M1a
(drop the `MEMORY.md` test) and M1b (drop the `gitlore_tier_paths` test) each
ship green across all twenty cases. With clause 3 present, clause 3 alone does
every exclusion any fixture exercises. That is not a test defect I can close
honestly: the scenarios the other two clauses defend against — a plain submodule
of a plain project, or a store enclosed by a memory store without being
registered in its `.gitmodules` — are unreachable through
`gitlore_guard_stale_merge_state`'s callers, which only ever walk
`gitlore_memory_stores`. Writing cases for them would mean calling the helper
directly with a hand-built shape no caller can produce, which pins the code
rather than the behaviour. Main's call whether to keep all three clauses as
defence in depth (fine, and cheap) or to simplify the predicate to `MEMORY.md`
plus the exclusion; either way the runbook should not claim clause 2 is what
excludes the host project, because it is not.

## 5. Three `CLAUDECODE` worlds

Full suite against unchanged code, three runs:

| world | result | detail |
| --- | --- | --- |
| `CLAUDECODE=1` (the dispatch's ambient value) | 16 passed, 4 failed | 13 `:367`, 14 `:387`, 16 `:440`, 17 `:461`; 15 and 18 green |
| `env -u CLAUDECODE` | 16 passed, 4 failed | identical lines and assertions; 15 and 18 green |
| `env CLAUDECODE=0` | 16 passed, 4 failed | identical lines and assertions; 15 and 18 green |

Identical in all three, as expected: nothing in the six cases reads a
`gitlore_say_for_agent_or_user` arm. Case 5 asserts a phrase the precedent emits
through a plain `printf … >&2`, which has no agent/user split; cases 4 and 6
assert an exit code and an index. The invariance is measured, not inferred.

## 6. Tree state

- `git diff scripts/` — empty. `git diff --exit-code scripts/lib/resolve.sh`
  returns 0; the file is byte-identical to HEAD.
- Modified in the tree: `tests/resolve_recovery.bats` (the RED dispatch's cases
  plus the three fixes in §3) and `plans/index-edit-propagation/runbook.md`
  (dirty by design, untouched here). Untracked:
  `plans/index-edit-propagation/reports/item-1-3-s1-red.md` and this report.
- Nothing staged, nothing committed. The only commands run were
  `scripts/run-bats.sh --jobs 1 tests/resolve_recovery.bats` and `shellcheck`.
- Final confirmation run, unchanged code: `16 passed, 4 failed` — cases 1, 2, 4,
  5 red on their intended assertions, cases 3 and 6 green.
