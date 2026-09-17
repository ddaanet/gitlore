# Item 2.2 / slice 2 — RED (guard)

## Test added

`tests/push_behind_vs_diverged.bats`: "a post-loop publication push refused by
policy is worded as a non-divergence failure, not as a moved remote", appended
after slice 2.2/1's test. Guard — recorded as such, holds against the current
tree.

Fixture: `setup_repair_race_on_aa` (slice 2.1/1's shared setup) plus
`push_tier_fact bb ...`, the same shape slice 2.2/1 uses, but no `git` stub: a
real `pre-receive` hook on `aa`'s bare remote (`decline_second_push_by_policy`,
new helper next to `decline_tier_pushes_recording`) counts pushes it receives
into a shared ledger file and accepts the first, declining every one after with
`declined by policy` on stderr.

## Why the ledger reads `aa aa `, not `aa bb aa `

Slice 2.2/1's stub intercepted `git`'s argv on the client side, so it could log
a call for `bb` regardless of what real git would do. With a real remote, `bb`'s
own push attempt (it is behind — `push_tier_fact bb` put its remote ahead) is
refused by git's own client-side fast-forward check before any pack is
transferred, so `bb`'s `pre-receive` never fires; and once the take
fast-forwards `bb` to exactly match `origin/live`, the loop's own "nothing to
publish" ancestry check (`resolve.sh:1405`, mirrored at the post-loop pass)
skips a second attempt entirely. `bb` never touches its remote's hooks in this
scenario — confirmed empirically: a first version of the test installed an
always-accepting logging hook on `bb`'s remote too, and it never fired (ledger
came back `aa aa `, not `aa bb aa `). That version is not in the committed test;
the hook was dropped as dead fixture rather than kept as a no-op.

`bb` having taken its own remote's fact
(`git -C memory/bb merge-base --is-ancestor "$bb_fact" live`) is the pin for
"`bb`'s push happened in between": that take is the same call that fetches and
repairs `aa` on top of `D`, so it is what sits between `aa`'s two pushes to its
own remote.

## Preconditions asserted before the wording

Before the wording assertions: `status -eq 1`; the ledger reads `aa aa ` (the
declined push is `aa`'s second, not its first); `bb` took `$bb_fact`; `aa`'s
local `live` is the repair commit with parent `$D`; `aa`'s *remote* `live` is
still `$D` (the second push never landed). Then: stderr contains
`declined by policy` (the hook's own text, relayed) and
`pushing tier 'aa' failed, and not because of divergence`; stderr does not
contain `The remote moved during the push`.

## Guard run

`scripts/run-bats.sh tests/push_behind_vs_diverged.bats --filter "worded as a non-divergence failure, not as a moved remote"`:
```
bats: 1 passed, 0 failed
```
Full file: `scripts/run-bats.sh tests/push_behind_vs_diverged.bats` — 20 passed,
0 failed.

`shellcheck tests/push_behind_vs_diverged.bats`: clean.

## Mutation (teeth)

In `scripts/lib/resolve.sh`, `gitlore_report_tier_push_failure`'s `case` pattern
was changed from `*"(fetch first)"*|*"(non-fast-forward)"*)` to `*)` — forcing
the divergence wording unconditionally. Filtered run:
```
not ok 1 a post-loop publication push refused by policy is worded as a non-divergence failure, not as a moved remote
#   `[[ "$output$stderr" == *"pushing tier 'aa' failed, and not because of divergence"* ]]' failed
```
Fails on the wording assertion, after every precondition (`status`, ledger,
`aa_live`, remote `live`, hook text) already passed — exactly the wording this
slice guards. Restored via `Edit`; `git diff scripts` is empty, and the guard
passes again in the restored tree.

## Result

No production code touched (mutation applied and reverted in place, diff
confirmed empty). No commit made.
