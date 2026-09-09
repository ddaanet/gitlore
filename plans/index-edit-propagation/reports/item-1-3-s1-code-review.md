# Item 1.3, slice 1 — code review

Reviewed: `git diff scripts/lib/resolve.sh` as GREEN left it, against
`plans/index-edit-propagation/runbook.md` Item 1.3 slice 1 and the mutation
matrix in `plans/index-edit-propagation/reports/item-1-3-s1-test-review.md` §2.

Verdict: the primary hypothesis **held**. Fixed in place, with two permanent
cases and their mutation proofs. Six suite runs green, `shellcheck` clean.
Nothing staged, nothing committed, no `just` recipe run.

## 1. The primary hypothesis — held, measured

**Staging the gitlink alone unblocked a composition that then destroyed the
merge it was staged to preserve.** As shipped by GREEN, a landed tier merge
recovered on the commit path was silently overwritten with the root index's
superseded text, committed, and reported as a success.

### Why the existing fixtures could not reach it, and what the probe changed

The lead's diagnosis of the fixture gap was right, and its proposed probe would
not have caught the defect. `gitlore_compose_down`
(`/Users/david/code/gitlore/scripts/lib/index-compose.sh:446`) resolves each
path against three lists — root's worktree bullets, the carrier's, and
**root at `HEAD:MEMORY.md`**:

```sh
    if [ "$o" = 1 ]; then
      gitlore_compose_pick "$path" < "$tmpd/root.bullets"
    elif [ "$t" = 1 ] && [ "$b" = 0 ]; then
      gitlore_compose_pick "$path" < "$tmpd/carrier.bullets"
    fi
```

A line the merge **adds** to the carrier is `o=0, t=1, b=0` — kept. So a probe
whose upstream side adds an index line goes green against the destructive
implementation and proves nothing. What the down projection rewrites is a line
root **also carries** (`o=1`): root's bullet text wins. The probe therefore has
the tier's `live` side **re-text an index line both surfaces already hold**.

That is now pinned in the permanent case's comment, so the next reader cannot
weaken the fixture back into the vacuous shape.

### The probe and its verbatim output

Temporary case, appended to `tests/resolve_recovery.bats`, run through
`scripts/run-bats.sh --jobs 1 -f PROBE`, then removed. Shape: mount `ddaanet`,
seed `- [shared](shared.md) — ours` and land it through the real `pre-commit` so
root's block holds `- [shared](ddaanet/shared.md) — ours`; build an upstream
commit on the tier's `live` that re-texts that same carrier line to
`— upstream text`; add a local **body** file so the tier's own commit touches no
index line and the merge cannot conflict; run `pre-commit` to prepare the merge;
land it with a bare `GITLORE_MEMORY_COMMIT=1 git commit --no-edit`; move HEAD
off it; then run the commit path and diff the carrier before and after.

**Against unchanged code (`git stash push scripts/lib/resolve.sh`):**

```
### run3 status=1
### run3 err: gitlore: the merge in <tmp>/memory/ddaanet landed as e5b3c927… before a checkout or reset moved HEAD off it; HEAD is restored to it and the leftover merge state cleared, so none of that merge is lost.
gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
tier 'ddaanet' is checked out at e5b3c927376c but the memory store records 8fe61d5c4c92: it was moved outside /gitlore:merge, and projecting the root index onto it would overwrite what it holds. …
### carrier AFTER the commit path:
- [shared](shared.md) — upstream text
### VERDICT: carrier UNCHANGED
```

**Against the slice as GREEN shipped it:**

```
### run3 status=0
### run3 err: gitlore: the merge in <tmp>/memory/ddaanet landed as 7c6664d1d819… before a checkout or reset moved HEAD off it; HEAD is restored to it and the leftover merge state cleared, so none of that merge is lost.
### carrier AFTER the commit path:
- [shared](shared.md) — ours
### root AFTER:
- [shared](ddaanet/shared.md) — ours
### VERDICT: carrier CHANGED by the commit path
--- carrier-before
+++ memory/ddaanet/MEMORY.md
@@ -3,4 +3,4 @@
-- [shared](shared.md) — upstream text
+- [shared](shared.md) — ours
```

Exit 0. The only message printed is the recovery's own reassurance that "none of
that merge is lost". The overwrite is then committed by the same run.

That is exactly the outcome `gitlore_compose_check_pins`' own header comment
(`scripts/lib/index-compose.sh:290-296`) exists to prevent — "nothing adopted
the carrier's newer text up into the root, so the next pass writes root's OLDER
text over it and reports a successful compose. That is a silent overwrite of
approved upstream facts, so this refuses rather than reports." Staging alone
satisfied the pin check without performing the adoption the check assumes.

## 2. The fix — the precedent followed in full, not partially

`gitlore_stage_recovered_gitlink` is now `gitlore_adopt_recovered_merge`
(`/Users/david/code/gitlore/scripts/lib/resolve.sh:319`), still placed
immediately after its only caller. The three-clause tier predicate is unchanged.
What changed:

```sh
  composed=$(gitlore_compose_up "$super" "$rel") || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'gitlore: the root index could not take %s'\''s lines, so the merge was left unrecorded rather than composed over — the next gate refuses the tier instead:\n' "$rel" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
    return 0
  fi
  if [ -n "$composed" ]; then
    printf '%s\n' "$composed" | sed 's/^/gitlore: /' >&2
  fi
  gitlore_git -C "$super" add -- MEMORY.md "$rel" \
    || printf 'gitlore: %s could not be staged in %s. …\n' …
```

Three decisions in that, each argued in the comment:

- **Up first, then the pair.** `gitlore_adopt_tier_into_root`
  (`scripts/lib/resolve.sh:1630`) is the precedent and the only shape in which a
  tier ahead of its pin may be adopted: `gitlore_compose_up`, then
  `add -- MEMORY.md "$tier"`. `docs/references/index-composition.md` states the
  same invariant — the merge continuation's adoption "is up-only and runs while
  the tier is legitimately ahead of the pin, before that path stages the moved
  gitlink." The change makes the recovery conform to that sentence rather than
  contradict it.
- **A failed up projection stages nothing.** Not the precedent's behaviour, and
  deliberately so: there HEAD and `live` have already moved, so not staging
  leaves a worse state; here not staging leaves *exactly today's loud abort*,
  which is the correct answer for a store whose root index cannot take the
  carrier. Pinned by a new case (§4).
- **No bookkeeping commit.** `gitlore_adopt_tier_into_root` also calls
  `gitlore_commit_tier_bookkeeping`. This helper runs inside a gate — including
  mid-`pre-commit`, where the hook is about to make its own commit — so the pair
  is left staged, which is D43's own degraded case. Residual noted in §7.

The rename is not cosmetic: the function no longer only stages. No caller
outside `gitlore_recover_landed_merge` names it, and no test does.

## 3. Mutation matrix against the corrected implementation (BASE4)

All applied in place to `scripts/lib/resolve.sh` and reverted; the suite is
`scripts/run-bats.sh --jobs 1 tests/resolve_recovery.bats`, 22 cases. Case
numbers are bats' own (13–18 are the RED/test-review cases, 19–20 the two added
here).

| mutation | result |
| --- | --- |
| BASE4 — the corrected implementation | 22 passed |
| M1a — drop clause 1 (`MEMORY.md`) | 22 passed (unpinned, as the test review measured) |
| M1c — drop clause 3 (the memory-root exclusion) | **RED 18** (host project) |
| M3 — clause 3 via cwd-relative `gitlore_memory_path` | **RED 18** |
| M2b — stage into the superproject's own superproject | **RED 13, 14, 16, 19** |
| M2c — fire on one rc-0 branch only | **RED 14** |
| M2d — staging failure silenced | **RED 17** |
| M2e — stage before HEAD is restored to the merge | **RED 13, 16, 19** |
| M2f — `add -A` instead of the named pair | **RED 13** |
| **M-UP — drop `gitlore_compose_up`, bare staging (the pre-fix implementation)** | **RED 19**, on the carrier assertion |
| **M-UPFAIL — stage the pair even when the up projection fails** | **RED 20** |

Every discrimination the test review measured survives the change, and the two
new cases each red on exactly one mutation, on their own assertion:

```
not ok 19 recovery: the upstream text a landed tier merge brought in survives the commit that adopts it
# (from function `assert_bullets' in file tests/helpers/tier-fixtures.bash, line 173,
#  in test file tests/resolve_recovery.bats, line 580)
#   `assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — upstream text'' failed
```

M2e now also reds case 19, which is a strengthening: the ordering constraint was
previously covered only by 13 and 16.

Note on M1/M1c under BASE4: with the pair staged rather than the gitlink alone,
the naive "stage whenever `--show-superproject-working-tree` is non-empty" no
longer reds case 15 — a parent with no root `MEMORY.md` makes
`git add -- MEMORY.md memory` fail on the pathspec, so nothing is staged and the
case passes for the wrong reason. Case 18 (M1c) still discriminates, and it is
the case the test review identified as the one that isolates the exclusion, so
the clause is still pinned. Flagging it because case 15's own comment claims a
proof that is now weaker than when it was written.

## 4. Cases added

Both in `/Users/david/code/gitlore/tests/resolve_recovery.bats`, ahead of "a
checkout-cleared merge whose HEAD is not the authority names both shas". No
existing case weakened, reordered or deleted.

1. **`recovery: the upstream text a landed tier merge brought in survives the commit that adopts it`**
   (`:529`). The probe from §1, made permanent, with `assert_bullets` rather
   than presence/absence pairs — the absent string here is a variant of the
   present one, which is the shape that goes vacuous. Three assertions after the
   exit code: the carrier still holds `— upstream text`; root took it up (so the
   first is the adoption's result, not a composition that declined to run); the
   pin equals the landed merge. The pin equality is placed **last** on purpose,
   and the comment says why — the overwrite also dirties the tier, so the tier
   loop commits it and the pin moves, which would make the case red one step
   away from its own point. Its mutation (M-UP) is named in the case's comment.

2. **`recovery: a landed tier merge the root index cannot take is left unstaged`**
   (`:603`). Pins the new fallback branch. Induced through
   `gitlore_compose_check`'s rule 3 — a root bullet prefixed with a tier that is
   not mounted, one line via `seed_root_bullet` — which is a reachable field
   state (a tier removed from `.gitmodules` with its lines left behind). Asserts
   the pin is **unchanged**, so the guard's refusal survives, plus the
   recovery's own rc 0 and restored HEAD. Its mutation (M-UPFAIL) is named in
   the comment.

## 5. The ordinary review

**Path derivation and symlinks — no defect.** Probed directly on this box (git
2.47.3) with a nested submodule reachable through a symlinked ancestor:

```
--- via real path ---
toplevel: /tmp/claude-1000/symprobe/real/outer/inner
superwt : /tmp/claude-1000/symprobe/real/outer
--- via symlinked path ---
toplevel: /tmp/claude-1000/symprobe/real/outer/inner
superwt : /tmp/claude-1000/symprobe/real/outer
```

Both `--show-toplevel` and `--show-superproject-working-tree` return the
resolved real path regardless of how the repo was reached, so the
`${abs#"$super"/}` strip holds. macOS's `/tmp` → `/private/tmp` is the same
mechanism (both go through git's realpath), so the FR11 violation the lead
feared is not reachable this way. The residual is the `|| abs="$store"` fallback
at `scripts/lib/resolve.sh:163` — if `--show-toplevel` itself fails, `abs` may
be relative and the strip is a no-op, leaving `rel` absolute and unequal to
`own_path`. That is pre-existing and unchanged by this slice; the staging would
then fail on the pathspec and report, rather than stage the wrong thing.

**Whitespace — no defect, run rather than read.** Temporary probe with a tier
named `my tier`, driven end to end through the real hook and the guard:

```
### guard status=0
### guard err: gitlore: the merge in <tmp>/memory/my tier landed as b79cd933… before a checkout or reset moved HEAD off it; …
### pin: b79cd9337c16afc32a2c7f66081251798c81396f  landed: b79cd9337c16afc32a2c7f66081251798c81396f
```

`rev-parse ":my tier"` reads the index directly, so the equality is direct
evidence the spaced path survived the expansion and the `add --`. Probe removed.

**The "pointer will be reset" claim — true, and now complete.**
`submodule update` reads the gitlink from the superproject's index (D43), so an
unstaged one is walked back at the next SessionStart; the precedent's comment
states the same mechanism for the same repo. The message previously named only
the tier; with the pair staged it now names `MEMORY.md` too, and says what an
unstaged root index costs — it would be left describing facts the tier no longer
holds.

**`gitlore_git` retry and partial staging — clean.** `gitlore_git`
(`scripts/lib/util.sh:329`) forwards `"$@"` intact and retries only on lock
errors, printing git's own stderr either way. `git add` writes the index through
`index.lock` plus rename, so a failure leaves the index untouched; there is no
partial-stage state to inherit. The multi-path form is not a weakness here: both
paths always exist by the time the clauses pass.

**Citations — three stripped.** The comment GREEN shipped cited
`scripts/lib/util.sh:185`, `scripts/lib/index-compose.sh:211` and
`scripts/lib/util.sh:83`, and said "measured — slice 1's test review found
removing it moves no case". Line numbers and a runbook-slice reference, both of
which shipped source does not carry. Replaced with the idiom named in prose and
the function named without a line number; the "measured" claim is dropped rather
than restated, since the comment cannot support it without pointing at `plans/`.
`grep -nE "\.sh:[0-9]|slice [0-9]|plans/|runbook|test review" scripts/lib/resolve.sh`
now returns nothing. (`D17 slice 3` elsewhere in `scripts/` is a decision id,
not a runbook slice, and stays.)

**Style.** The embedded single quote now uses `'\''`, matching
`gitlore_adopt_tier_into_root`'s own `printf` rather than the `'"'"'` form.
`[ -n "$composed" ] && printf …` was made an `if`, so the function cannot return
1 from a trailing test under errexit.

**Placement.** Entry point first: the helper stays defined immediately after
`gitlore_recover_landed_merge`, its only caller.

**Hook environment.** The new `add` targets the memory store, the same repo the
commit path's existing `gitlore_git -C "$mempath" add -A` writes from inside the
hook, so the `GIT_INDEX_FILE` handoff this depends on is already exercised by
`tests/git_hook_pre_commit.bats` and `tests/integration_gitlink_staging.bats`.
The memory root returns before any write, so the parent's in-flight index is
never touched.

## 6. Suites

`scripts/run-bats.sh --jobs 1`, never bare `bats`, never piped through `tail`.

| suite | `CLAUDECODE=1` | `env -u CLAUDECODE` | `CLAUDECODE=0` |
| --- | --- | --- | --- |
| `tests/resolve_recovery.bats` | 22 passed, 0 failed | 22 passed, 0 failed | 22 passed, 0 failed |
| `tests/resolve.bats tests/tier_divergence.bats tests/commit_memory.bats tests/index_compose.bats` | 109 passed, 0 failed | 109 passed, 0 failed | 109 passed, 0 failed |

Invariant across all three worlds, as expected: nothing on this path reads
`gitlore_say_for_agent_or_user`'s split — the recovery's own report already used
it before the change, and both new messages are plain `printf … >&2`.

`shellcheck scripts/lib/resolve.sh` — clean.
`shellcheck tests/resolve_recovery.bats` — clean.

Per the dispatch, `just precommit`, `just lint`, `just test-unit`,
`just test-integration` and `just format-docs` were not run.

## 7. Residuals, for the orchestrator

- **The guard now writes and stages outside the commit path.**
  `gitlore_guard_stale_merge_state` is also called from `gitlore_push_stores`,
  `gitlore_merge_stores` and `scripts/resolve.sh`. In those contexts the
  recovery now writes root's `MEMORY.md` and stages a pair, where before this
  item it wrote nothing. The staging half was already in scope as GREEN shipped
  it; the write is new with this fix and is the same write `/gitlore:merge`
  performs on the same state, so it is in band — but it is worth a line in the
  design record, which Item 1.3 as written does not have.
- **The staged pair leaves the store dirty.** `gitlore_adopt_tier_into_root`
  follows its staging with `gitlore_commit_tier_bookkeeping` precisely so an
  explicit take leaves a clean store (D49). This helper does not, so after a
  recovery from a push or a session gate, memory is dirty and the next commit
  demands an approved summary for content the user did not author. Inherent to
  the item rather than to the fix — the bare staging had the same effect — but
  the precedent's answer exists and was deliberately not taken here, because
  creating commits from inside a gate is a design call and mid-`pre-commit` it
  would be wrong. Worth deciding rather than inheriting.
- **The runbook's Item 1.3 slice 1 text is now incomplete.** It specifies the
  predicate and the staging and says nothing about the up projection, which this
  review found to be the load-bearing half. `plans/` and `docs/` were out of
  scope, so neither was touched.
- **Case 15's mutation proof is weaker than its comment claims** — see the note
  at the end of §3. Not weakened by me; the comment was written against the
  gitlink-only implementation.

## 8. Tree state

- Modified: `scripts/lib/resolve.sh` (74 insertions over HEAD),
  `tests/resolve_recovery.bats` (305 insertions over HEAD — the 198 inherited
  plus 107 for the two new cases), and `plans/index-edit-propagation/runbook.md`
  (dirty by design, untouched here).
- Untracked: the three prior Item 1.3 reports and this one.
- Nothing staged, nothing committed, no branch created or switched. Every probe
  file used during the review was removed and the suite file restored byte-exact
  before the permanent cases were added.
