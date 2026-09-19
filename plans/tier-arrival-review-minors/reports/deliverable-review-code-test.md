# Deliverable review — CODE and TEST, `plans/tier-arrival-review-minors`

Baseline: `outline.md` (design) and `runbook.md` (authoritative item contracts). Job range `3502a86..00584a1`; every finding re-checked against HEAD (`da6f651`). Later commits (`eabe091`, `954edd3`, `eac510c`, `51dd540`, `4eb1b50`, `0c15a51`) touch `gitlore_compose_check_pins`, `gitlore_emit_merge_directive`, `compose_merged_indexes`' state-file recording and the index merge — none of them touch a region this job changed, so every job line still stands as committed.

Verification performed: `scripts/run-bats.sh tests/push_behind_vs_diverged.bats` → 21 passed, 0 failed. A read-only probe of `gitlore_repair_index` under `$TMPDIR` (source the library, three unterminated fixtures, `od -c` on input and output) exercised three terminator cases the suite does not: an unterminated welded last line (tail stays last, stays unterminated), the same with the tail dropped as a duplicate (head becomes last, gains one newline), and an unterminated last line dropped as a duplicate (survivor gains one newline). All three follow the Phase 3 rule. No file was modified; `git diff --stat` is empty apart from this report.

## Critical

None.

## Major

None.

## Minor

### 1. The post-loop pass reports a tier with no remote as a generic push failure

`scripts/lib/resolve.sh:1510-1523` — axis: error signaling / robustness. Severity: Minor. **Verified by reading only.**

The tier loop skips a tier with no local `live` (`:1405`) *before* it checks `remote.origin.url` (`:1406-1412`), so a tier that has no remote and no `live` never produces the loop's dedicated `tier '<t>' has no remote configured, so nothing written there is being shared.` message. If a mid-loop take (`:1435` or `:1462`) then gives that tier a local `live`, the post-loop pass reaches it, has no remote check of its own, and its `push origin live` fails with git's raw `'origin' does not appear to be a git repository`, reported through `gitlore_report_tier_push_failure` as `pushing tier '<t>' failed, and not because of divergence`. The outline's claim that "a tier with no remote never reaches the pass, because the loop has already returned 1" holds only for tiers that already had a `live`. Narrow and self-recovering (still exit 1, still a message), but the diagnosis sends the reader at a push problem rather than at an unmounted remote. A `[ -n "$(git -C "$tierpath" config --get remote.origin.url || true)" ] || continue` in the pass, or reusing the loop's message, closes it.

### 2. The behind arm's retry push was rewired beyond Item 2.2's named callers, with no test

`scripts/lib/resolve.sh:1472` — axis: conformance / test coverage. Severity: Minor. **Verified by reading; already recorded as recommendation 6 of `reports/tdd-audit.md`.**

Runbook Item 2.2 names three callers for `gitlore_report_tier_push_failure`: the new pass, the outer `*)` arm, and the inner `*)` arm under `gitlore_classify_refusal`. The GREEN for slice 2.2/1 also routed the behind arm's retry push through it, so a `(non-fast-forward)` refusal of that retry now gets the moved-remote wording instead of the previous "not because of divergence". The new wording is the more accurate one for that call site (the push follows a fetch and a take, so a non-fast-forward there *is* a remote that moved), so this reads as an improvement rather than a regression — but it is an unrequested behaviour change and no test pins it. A stub failing the *second* `bb push -q origin live` in the behind-arm fixture would.

### 3. The pass's `origin/live`-missing branch and its skip conditions are untested

`scripts/lib/resolve.sh:1513-1517` — axis: test coverage. Severity: Minor (arguably Major; flagged transparently). **Verified by reading.**

Item 2.1's "What changes" specifies three behaviours the slice list does not test: skipping a tier with no checkout, skipping a tier with no local `live`, and pushing when `origin/live` is missing (`[ -z "$origin_live" ]`). All four existing pass tests run with `origin/live` present and both tiers checked out, so the `-z` arm and both `continue`s are dead in the suite. A plausible mutant — dropping the `[ -z "$origin_live" ] ||` disjunct — survives every test in `tests/push_behind_vs_diverged.bats`, because `merge-base --is-ancestor live ""` fails and takes the same branch. That makes the assertion set insensitive to that half of the condition. I rate it Minor because the runbook's own slice list is the test contract and does not call for it; if the item contract is read as the specification, it is a Major gap.

### 4. The refusal header and its `gitlore:   ` prefixing are emitted in two places

`scripts/lib/resolve.sh:2049-2050` vs `:2130-2131` — axis: modularity / excess. Severity: Minor. **Verified by reading.**

The unrepairable arm reproduces the header string `gitlore: the root index could not take %s's lines:` and the `printf '%s\n' … | sed 's/^/gitlore:   /'` emission of `gitlore_adopt_report_refusal_and_walk_back` verbatim, because it needs the filtered line list rather than `$composed`. Two copies of one user-visible string means a later reword has two sites; the Phase 7 quote sweep would have to find both. A two-line `gitlore_adopt_say_refusal <label> <lines>` helper called by both would remove the duplication without changing any output.

### 5. `tests/merge_memory.bats:1025` clobbers `$stderr` mid-test

`tests/merge_memory.bats:1025` — axis: test robustness. Severity: Minor. **Verified by reading.**

`run ! grep -Eq '^gitlore:   .*ddaanet/MEMORY\.md: ' <<<"$stderr"` overwrites `$output`, `$stderr` and `$status` at a point where eight assertions follow. Those assertions happen to use the pre-saved `$all` and fresh `git` calls, so the test is correct today, but any later assertion written against `$stderr` below that line would silently read the `grep` run's empty stderr and pass vacuously. `[[ "$stderr" != *…* ]]` with a glob, or grepping a saved copy, avoids the hazard; the sibling test at `:1056` already uses the `[[ != ]]` form.

## Fixed since

None. No finding from the job's diff has been fixed by later work — the later commits do not touch the job's regions, and each finding above was re-read at HEAD.

## Requirement coverage

| ID | Requirement | Status | Code at HEAD | Test at HEAD |
|---|---|---|---|---|
| M1 | Unrepairable arm prints non-carrier problems and the two-fix remedy | covered | `scripts/lib/resolve.sh:2041-2055` | `tests/merge_memory.bats:1037` |
| M2 | Transient arms print the full refusal with `Run /gitlore:merge again.` | covered | `scripts/lib/resolve.sh:2018-2021, 2061-2069, 2071-2075, 2076-2080` | `tests/merge_memory.bats:625, 705, 737, 785` (commit build, `mktemp`, checkout follow, `live` advance; arrival read, pin read and rewrite share the `repair=""` path at `:2066-2069`) |
| M3 | Walk-back names what `live` holds | covered | `scripts/lib/resolve.sh:2129, 2132, 2147, 2156` | `tests/merge_memory.bats:948` (`keeps the repair.` / not `keeps what arrived`), `:737`, `:991` |
| M4 | One reporter classifies a failed tier push | covered | `scripts/lib/resolve.sh:1625-1645`, callers `:1472, 1489, 1495, 1520` | `tests/push_behind_vs_diverged.bats:709` (non-fast-forward → moved remote), `:777` (policy → not-divergence); the `:1472` caller is untested (Minor 2) |
| M5 | Mid-push repair race — post-loop publication pass | covered | `scripts/lib/resolve.sh:1502-1524` | `tests/push_behind_vs_diverged.bats:616, 629` (both race variants), `:665` (behind arm's own repair survives a later failure); skip and missing-`origin/live` branches untested (Minor 3) |
| M6 | Repair preserves line terminators | covered | `scripts/lib/index-compose.sh:355-360, 419-428, 443-449` | `tests/index_compose.bats:1519, 1536, 1556`, plus `:1334` unchanged; probe above confirms the weld-split cases |
| M7 | Scratch directory under `$TMPDIR` | covered | `scripts/lib/resolve.sh:2018, 1998-1999` (comment) | `tests/index_compose.bats` n/a; `tests/merge_memory.bats:661` (location), `:705` (`mktemp` fails), plus `repair_scratch_dirs` cleanup assertions at `:558, 625, 661, 991` |
| M8 | Comment verb "adopt past" | covered | `scripts/lib/index-compose.sh:270` | n/a (comment) |
| M9 | `(K3)` dropped from the section header | covered | n/a | `tests/index_compose.bats:1312` |
| M10 | Attribution test gains a suffix decoy | covered | n/a | `tests/index_compose.bats:1282, 1289-1291` |
| M11 | Unrepairable test: no carrier prefix, memory `HEAD` unchanged | covered | n/a | `tests/merge_memory.bats:1017, 1025` |
| M12 | S1 abort through both entry points | covered | n/a | `tests/git_hook_pre_commit.bats:433` (root weld through the hook, status 1, restamp), `:391` (`-eq 1`, `live` pin at `:399` and unmoved assertion at `:426`) |
| M13 | Three untested rule paths | covered | n/a | rule 4 dirty-file abort `tests/commit_memory.bats:205`; rule 4 merged-root gate `tests/resolve_compose.bats:640`; rule 2 advisory arm already covered by `tests/commit_memory.bats:824`, mutant-proven in `reports/item-5-3.md` rather than by a new test, as the runbook directs |
| M15 (harness) | Three pre-landing "was not committed" exits | covered | `scripts/resolve.sh:320-341`, residual comment `:105-109` | `tests/resolve_compose.bats:458` (refused commit, tightened to `-eq 1` with an ordering glob), `:494` (build fails), `:547` (`mktemp` fails) |

Notes on the table:

- M2's arrival-read, pin-read and rewrite arms are not individually tested; all three fall through to the same `[ -z "$repair" ]` reporting path as the commit-build arm, which `tests/merge_memory.bats:625` covers, and the runbook's slice list asks for exactly the four tests present.
- M13's rule-2 entry is the one requirement satisfied by an existing test plus a mutation proof rather than by a new assertion. That is what Item 5.3 specifies, and `reports/item-5-3.md` records the failing mutant, so it is covered rather than partial.
- Phase 3 ships a third terminator test (`tests/index_compose.bats:1556`, the unterminated trailer) beyond the runbook's two slices. It is not excess: it is the only test in which the tagged element survives the repair in place while a stray moves ahead of it, i.e. the `p3tagged -eq last_i` branch at `:449`.

## Axis sweep

- **Conformance.** Every item contract is implemented as the runbook words it, with one divergence (Minor 2) and one unimplemented sub-clause in the test dimension only (Minor 3). The outline/runbook differences the runbook explains (scratch `mktemp` arm added as its own line; the behind arm keeping its retry push, which the outline had said to drop) are recorded in the runbook text and are not divergences.
- **Vacuity.** No new assertion is vacuous. Each negative assertion (`!= *"Fix the store"*`, `!= *"not because of divergence"*`, `!= *"the merge commit was refused"*`) is paired with a positive one in the same test, and the premise assertions (`mktemp-hit`, `log-hits`, `$count_file -eq 3`, the push-order pin `"aa bb aa "`, the offered-sha ledger) pin that the stub actually fired on the intended call rather than on a forwarded one.
- **Whitespace safety.** `gitlore_report_tier_push_failure` and the pass quote every expansion; `merge-base --is-ancestor live "$origin_live"` is quoted; the `${line#"$tierpath/MEMORY.md: "}` strip quotes its pattern; `find … -print0` / `read -r -d ''` is used in the new hook test's backdating loop.
- **`set -e` blind spots.** `merge_msgfile=$(mktemp …) || { … }` is the correct shape for a command-substitution assignment, and each `||` group removes the scratch file before writing to stderr, per the runbook's reasoning. `other_lines=$( … )` at `:2041` is an unguarded command-substitution assignment, but its `while` loop always ends on `continue` or `printf` (status 0), and the whole function runs under a suspended `errexit` (`… || return 1` at `:1983`), so there is no abort path.
- **bash 3.2 / BSD.** `local -a p2=()`, `${#p1[@]}`, `[ "$i" -ne "$tagged" ]` and the `case` prefix matches are all 3.2-safe; the empty-array expansion is still guarded by `[ "${#p1[@]}" -gt 0 ]`. No GNU-only flag was added (`find -mindepth/-maxdepth/-print`, `ls -d`, `sed 's/^/…/'`, `tr -d` are all BSD-portable).
- **Source hygiene.** No added line in `scripts/` cites `plans/`, `memory/`, a runbook item, slice or line number.
