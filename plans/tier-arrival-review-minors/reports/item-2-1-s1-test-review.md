# Item 2.1 / Slice 1 — test review

Scope: the two new tests in `tests/push_behind_vs_diverged.bats` and their
helpers. All findings fixed in place; nothing committed; no implementation file
touched.

## Final run

`scripts/run-bats.sh tests/push_behind_vs_diverged.bats`: 15 passed, 2 failed.

- `not ok 16 … (behind)` — line 562, the last assertion
  (`cat-file -e "$aa_live^{commit}"` on `aa`'s remote).
- `not ok 17 … (ahead-of-HEAD)` — line 577, the last assertion, same check.

Both lines are the final `[ "$status" -eq 0 ]` after the `cat-file` `run`, so
every earlier precondition executed and held. `shellcheck -x` is clean (the
project lints at default severity, info included).

## Findings and fixes

1. **Major — the test could never go green.** The "hook fired" assertion was
   `[ "$(… .bare-aa.git rev-parse live)" = "$d" ]`. A correct fix pushes the
   repair on top of D, so `aa`'s remote `live` ends at the repair, not D: the
   test would have stayed red on that line after the fix. Replaced by two
   fix-independent checks: the one-shot hook file is gone, and D is an ancestor
   of `aa`'s remote `live`.

2. **Major — setup failures were silent.** `d=$(setup_repair_race_on_aa)` ran
   the whole fixture in a command substitution, where bash does not inherit
   errexit: any failing step except the final `printf` was ignored, and any
   stdout a helper printed would pollute `$d`. Likewise `push_side_ref_child`'s
   status was that of its trailing `rm -rf`, not of the push. Now
   `setup_repair_race_on_aa` is called directly and sets `$P`/`$D`; every step
   in the two scratch helpers carries `|| return 1`; the sha capture is the
   helper's last command.

3. **Major — preconditions were incomplete or inferred.** Push exit 0 was
   checked first (fine); the repair was only "`live` differs from D and contains
   it", which any later commit would satisfy. Now `assert_aa_repaired_mid_loop`
   (called before the defect assertion) checks: status 0; hook gone and D
   reached `aa`'s remote; `aa`'s local `live` has exactly D as parent; that
   commit's `MEMORY.md` holds the duplicated bullet once; the output names
   `repaired aa's arrival`; memory's remote records it as `aa`'s gitlink. The
   setup also asserts P is memory's recorded `aa` pin, P is not on `aa`'s remote
   yet, and D sits on the side ref.

4. **Minor — neither variant proved its own `bb` arm ran.** Added: behind
   asserts `bb`'s remote fact is in `bb`'s local `live`; ahead-of-HEAD asserts
   the adoption message for `tier 'bb'` and that `bb`'s stranded commit reached
   `bb`'s remote. Since `aa`'s iteration has no take to run (its HEAD equals
   `live`, and its push of P succeeds), the repair of `aa` can only come from
   `bb`'s iteration — after `aa`'s pushed.

5. **Minor — hygiene.** Scratch clone moved from `${TMPDIR:-/tmp}` to
   `$BATS_TEST_TMPDIR` (no cleanup needed). `advance_tier_past_remote` uses
   `git -C` rather than a `cd` subshell. A shared assertion helper reading bats'
   `$status`/`$output` tripped SC2030/SC2031; it takes them as arguments
   instead.

## Fixture fidelity (check 3)

Matches the spec: `aa` then `bb` via `mount_tier_at_live`, manifest `aa bb`,
memory composed/committed/published; P adds `plain.md` with no index line,
`live` at P, recorded as memory's pin before the push; D is a child of P
appending `- [A](a.md) — x` twice, pushed to `refs/heads/stash-d`; a
self-removing `post-receive` running `git update-ref refs/heads/live D`.
Variants use `push_tier_fact bb` and `strand_live_ahead_of_pin bb`.

## Will it go green for the right fix (check 4)

Probed empirically in a scratch `git archive` copy of HEAD with this file:
adding a post-loop pass over `gitlore_tier_paths` that pushes `live` when it is
not an ancestor of `origin/live` turns the whole file green (17 passed), with
the tests unedited. The current code already re-pushes the tier being processed
(`bb`, via the behind arm's retry and the ahead-of-HEAD fall-through push) and
the tests are red against it, so a current-tier-only fix stays red. Probe
directory removed.

No UNFIXABLE items.
