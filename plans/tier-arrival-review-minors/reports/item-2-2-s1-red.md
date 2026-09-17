# Item 2.2 / slice 1 — RED

## Test added

`tests/push_behind_vs_diverged.bats`: "a repair the post-loop pass cannot
publish is worded by the moved remote, not by policy", appended after "a
behind arm's repair survives a later tier's failure".

Fixture: `setup_repair_race_on_aa` (slice 2.1/1's behind-variant setup) plus
`push_tier_fact bb ...` — identical to the "(behind)" test at
`tests/push_behind_vs_diverged.bats:553`. A `git` stub is put on `PATH` for
`run --separate-stderr bash "$CMD"` only; it counts calls whose argv ends
`aa push -q origin live` into a counter file and, on the 2nd such call, prints
`! [rejected]        live -> live (non-fast-forward)` to stderr and exits 1;
every other call (including the first `aa ... push` call) execs the real git.

## Call 2 is the post-loop pass, not the loop's retry

Confirmed by reading the code path (`scripts/lib/resolve.sh:1308-1475`), and by
a temporary `echo "DEBUG: $output$stderr" >&2` added before the wording
assertions during this RED run (removed before finishing):

- `aa` is processed first (`.gitmodules` order: `mount_tier_at_live aa` then
  `bb`). Its own loop iteration pushes P — `origin/live` for `aa` was still at
  the pre-fixture base, so this push is a fast-forward and succeeds (call 1).
  This triggers the one-shot `post-receive` hook `setup_repair_race_on_aa`
  installed, snapping `aa`'s *remote* `live` to `D` (the duplicate-bullet
  arrival).
- `bb` is behind (`push_tier_fact bb` advanced its remote). Its `push`
  fails `(non-fast-forward)`, classified `behind`, which runs the take pass
  (`GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores`). The take fetches every tier
  root-first, discovers `aa`'s remote is now at `D`, and repairs the
  duplicate bullet into a new commit on top of `D` — entirely in `aa`'s local
  `live`, no push. The behind arm's own retry push
  (`resolve.sh:1405-1414`) then checks ancestry on `$tierpath`, which at that
  point in the loop is `bb`'s path, and pushes `bb`, not `aa` — confirmed by
  the debug output, which showed `tier 'bb' — fast-forwarded to …` and no
  second `aa` push before the loop ended.
- The post-loop pass (`resolve.sh:1457-1475`) re-walks every tier. `aa`'s
  cached `refs/remotes/origin/live` is stale at P (the tracking ref git
  updated after call 1's own push, before the hook moved the real ref to
  `D`), so `live` (now the repair commit, a descendant of `D`, which is a
  descendant of `P`) is not an ancestor of the cached `P` — the pass pushes
  `aa` again. That is call 2, the one the stub fails.

The debug capture (removed) showed, before the fixture's own pre-existing
"not because of divergence" line:
```
gitlore: tier 'aa' — fast-forwarded to ef5a9d4
gitlore: repaired aa's arrival: dropped a duplicate pointer line: - [A](a.md) — x
gitlore: tier 'aa' — the repair is committed in its local 'live', and this push publishes it.
...
gitlore: tier 'bb' — fast-forwarded to dbcae6f
...
gitlore: pushing tier 'aa' failed, and not because of divergence. git said:
! [rejected]        live -> live (non-fast-forward)
```
confirming the repair happened, `bb` (not `aa`) was the loop's own retry
target, and the failing push named is `aa`'s.

## Result

`scripts/run-bats.sh tests/push_behind_vs_diverged.bats --filter "moved remote, not by policy"`:

```
not ok 1 a repair the post-loop pass cannot publish is worded by the moved remote, not by policy
# (in test file tests/push_behind_vs_diverged.bats, line 690)
#   `[[ "$output$stderr" == *"The remote moved during the push"* ]]' failed
```

Fails on the positive wording assertion (`The remote moved during the push`),
not on the negative one, not on setup, and not on status — the preconditions
(`counter == 2`, `status -eq 1`, `aa`'s local `live` is the repair commit with
parent `$D`) all pass first; the current outer `*)` arm always emits "not
because of divergence" regardless of git's reason, which is exactly the
defect Item 2.2 fixes.

`shellcheck tests/push_behind_vs_diverged.bats`: clean.

No production code touched. No commit made.
