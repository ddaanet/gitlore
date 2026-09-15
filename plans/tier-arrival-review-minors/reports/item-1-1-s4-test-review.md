# Item 1.1 / slice 4 — test review

**Test:** `a repair whose checkout follow fails walks back and keeps the repair`
(`tests/merge_memory.bats`).

**Verdict:** fixed, still red on an assertion. shellcheck clean. Nothing
committed.

## Mechanical

`scripts/run-bats.sh tests/merge_memory.bats --filter 'checkout follow fails'`
fails on an assertion, not an ERROR. After the fixes the first failing
assertion is the refusal header (line 664). Today's arm calls
`gitlore_adopt_walk_back_tier` directly and prints no header.

## Findings and fixes

1. **Refusal header missing (fixed).** The slice list omits it, but Item 1.1's
   Changes require the checkout-follow arm to go through
   `gitlore_adopt_report_refusal_and_walk_back` with `$composed`. Added the
   sibling slice 2 assertion: the header, then
   `gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md`. Also
   added `!= *"Fix the store"*`. A mutant that passes `the repair` and the
   right remedy to the bare walk-back helper now fails.
2. **`could not follow` was ambiguous (fixed).** The take's own fast-forward
   failure (`resolve.sh:1695`, "its 'live' advanced but its working tree could
   not follow") and `gitlore_adopt_advanced_live` (`:1827`) both contain the
   substring. If the stub hit the wrong call, the assertion would still pass.
   The test now asserts the arm's own line, `its repair advanced its local
   'live' but its working tree could not follow`, which the Changes keep
   ("Each keeps its own `could not …` line").
3. **Remedy tied to the walk-back (strengthened).** The two separate substrings
   `keeps the repair.` and `Run /gitlore:merge again.` are now one assertion:
   `its local 'live' keeps the repair. Run /gitlore:merge again.` Today's
   walk-back prints `keeps %s. %s`, so the remedy must come from the walk-back
   line and not from some other message.
4. **The repair commit's identity (strengthened).** Added a subject check
   (`Repair the MEMORY.md structure ddaanet received`) next to the parent
   check. `live` must hold the repair commit, not just some child of the
   arrival.

## Checked, no change needed

- **Counter.** The count file is at `$BATS_TEST_TMPDIR/checkout-live-count`.
  The pattern `*" checkout -q --detach live "*` needs the trailing space, so
  the walk-back's `checkout -q --detach <old_gitlink>` never matches. Both
  paths are quoted inside the stub, so a spaced `BATS_TEST_TMPDIR` is safe.
  `gitlore_git` retries only on lock errors, so a failure cannot be counted
  twice. Only the 2nd match fails.
- **PATH scope.** The stub is on `PATH` only for the `run` under test, the same
  shape as the slice 2 sibling.
- **Arrival.** `remote_sha` comes from `push_tier_fact`, independent of `live`.
  `rev-list --parents -n 1 R = "R remote_sha"` also implies `R != remote_sha`,
  so the check is not vacuous.
- **Pin.** `pin` is captured before the arrival is pushed. When the checkout
  fails, the take's fast-forward has already put `HEAD` on the arrival. So
  `HEAD = pin` needs the walk-back to have run.

## Probe against the intended arm

As a probe, I changed the arm in `scripts/lib/resolve.sh` to
`gitlore_adopt_report_refusal_and_walk_back … "$composed" "Run /gitlore:merge
again." "the repair"`. The test passed: 1 passed, 0 failed. So the full
assertion set can be met by the Changes as written. The file was restored from
a byte copy afterwards, and `git status --porcelain scripts/lib/resolve.sh` is
empty.
