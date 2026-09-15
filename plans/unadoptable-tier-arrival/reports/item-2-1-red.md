# Item 2.1 — RED report

`scripts/lib/index-compose.sh`: added an inert stub `gitlore_repair_index` (`:`
body, prints nothing, returns 0, touches nothing) placed directly after
`gitlore_compose_check_index`, whose rules 1/4/6 it repairs. No implementation
written. Commit: none (uncommitted tests + stub are this dispatch's end state).

All eight slices' tests are in `tests/index_compose.bats`, appended after "a
failing check writes nothing at all". Fixtures are plain scratch files/dirs
(`file.md`, `pin.md`, `tier/`) rather than a full tier mount — the function
takes three paths and has no opinion about what else lives beside them.

## Slice 1 — "repairing a clean index changes nothing"

**Verdict: guard.** Holds against the inert stub (no-op leaves the file
untouched, prints nothing, returns 0 — exactly what "no edit" looks like).

Mutation-red proof: stub changed to `printf '\n' >> "$1"` (an observable edit
that prints nothing).

```
not ok 1 repairing a clean index changes nothing
  `cmp -s clean.md clean.before' failed
```

Restored via Edit back to `:` and diffed against the pre-mutation stub —
identical. (`git checkout HEAD --` was not used, since HEAD predates the stub
itself.)

## Slice 2 — "an identical duplicate is dropped"

**Verdict: red.**

```
not ok 1 an identical duplicate is dropped
  `[ "$output" = "dropped a duplicate pointer line: - [A](a.md) — x" ]' failed
```

## Slice 3 — welds

"a welded line is split before the second bullet" — **red**:

```
not ok 1 a welded line is split before the second bullet
  `[ "$output" = "split a welded line before welded_b.md" ]' failed
```

"a three-bullet weld splits twice" — **red**:

```
not ok 1 a three-bullet weld splits twice
  `[ "$output" = "$(printf 'split a welded line before welded_b.md\nsplit a welded line before welded_c.md')" ]' failed
```

## Slice 4 — welds left alone

"a weld naming no file in the tier is left unchanged" — **guard.** Holds against
the inert stub.

Mutation-red proof (same `printf '\n' >> "$1"` mutation):

```
not ok 1 a weld naming no file in the tier is left unchanged
  `cmp -s file.md file.before' failed
```

"a link the check does not report as a weld is left unchanged" — **guard.**
Holds against the inert stub.

Mutation-red proof:

```
not ok 1 a link the check does not report as a weld is left unchanged
  `cmp -s file.md file.before' failed
```

Both restored via Edit back to `:`; `git diff scripts/lib/index-compose.sh`
confirmed only the intended stub addition remains.

## Slice 5 — "an interleaved non-bullet line moves to the start of the trailer"

**Verdict: red.**

```
not ok 1 an interleaved non-bullet line moves to the start of the trailer
  `[ "$output" = "$(printf 'moved a non-bullet line out of the pointer block: first stray line\nmoved a non-bullet line out of the pointer block: second stray line')" ]' failed
```

## Slice 6 — differing duplicates

Main case, "a differing duplicate keeps the line the pin lacks" — **red**:

```
not ok 1 a differing duplicate keeps the line the pin lacks
  `[ "$output" = "dropped a duplicate pointer line: - [A](a.md) — first hook" ]' failed
```

Row "new to both keeps the first" — **red**:

```
not ok 1 a differing duplicate: new to both keeps the first
  `[ "$output" = "dropped a duplicate pointer line: - [A](a.md) — second hook" ]' failed
```

Row "known to both keeps the first" — **red**:

```
not ok 1 a differing duplicate: known to both keeps the first
  `[ "$output" = "dropped a duplicate pointer line: - [A](a.md) — second hook" ]' failed
```

Row "a pin with no carrier keeps the first" — **red**:

```
not ok 1 a differing duplicate: a pin with no carrier keeps the first
  `[ "$output" = "dropped a duplicate pointer line: - [A](a.md) — second hook" ]' failed
```

## Slice 7 — "welds are split before duplicates are resolved"

**Verdict: red.**

```
not ok 1 welds are split before duplicates are resolved
  `[ "$output" = "$(printf 'split a welded line before welded_b.md\ndropped a duplicate pointer line: - [B](welded_b.md) — b')" ]' failed
```

## Slice 8 — "a rewrite that cannot be written leaves the file unchanged"

**Verdict: red** (asserts `[ "$status" -eq 1 ]`, which bites against the stub's
rc 0 — the return-code assertion was written to bite per dispatch instructions).

```
not ok 1 a rewrite that cannot be written leaves the file unchanged
  `[ "$status" -eq 1 ]' failed
```

Uses the `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"` /
`chmod a-w <dir>` / `chmod u+w <dir>` pattern from
`tests/git_hook_pre_commit.bats:433,456,459`.

## Whole-suite run

`scripts/run-bats.sh tests/index_compose.bats` (no filter): 69 passed, 10 failed
— the 4 guard tests (slice 1, slice 4 ×2, counted once each; slice 1 is one
test) plus the 65 pre-existing tests all pass; the 10 non-guard new tests
(slices 2, 3×2, 5, 6×4, 7, 8) fail exactly as shown above, with no
`ImportError`/`AttributeError`-equivalent (no "command not found" or
unbound-variable failures — every failure is on the test's own assertion).

## Lint

`shellcheck -x scripts/lib/index-compose.sh` — clean.
`shellcheck -x tests/index_compose.bats` — clean.
