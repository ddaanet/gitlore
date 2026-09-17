# Item 4.1/2 — test review

Verdict: the test was red for the right reason as delivered. Four findings, all
fixed in `tests/resolve_compose.bats`; the test is still red on the same
assertion, and no production file changed.

## 1. Mechanical

`scripts/run-bats.sh tests/resolve_compose.bats`, foreground, unpiped, against
unmodified `scripts/resolve.sh`:

```
not ok 14 a message build failure leaves no message file behind and keeps the merge prepared
# (in test file tests/resolve_compose.bats, line 457)
#   `[[ "$stderr" == *"gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared."* ]]' failed

bats: 23 passed, 1 failed
```

Line 457 is the build-line wording assertion. The other 23 tests pass.
`shellcheck --shell=bash tests/resolve_compose.bats` is clean.

## 2. Right reason

Every assertion ahead of the wording line passes against the unfixed script —
status 1, the stub-hit proof, `MERGE_HEAD`, the merge-state file, the staged
synthesis in both stores, and the absent message file. The one thing missing
from the run is the stderr line, which is exactly what GREEN adds at
`scripts/resolve.sh:312-313`.

Confirmed from the other side with a temporary probe: the `||` brace group at
`scripts/resolve.sh:312-313` was expanded to `rm -f` then the build line then
`exit 1`, the suite re-run (`24 passed, 0 failed`), and the probe reverted —
`git status --porcelain scripts/` is empty and `git diff --stat` shows only
`tests/resolve_compose.bats`. That run is what validates the assertions *after*
the wording line, which a red run never reaches.

## 3. The stub hits the intended call — verified independently

`grep -rn -- 'log .*--format' scripts/` and `grep -rn -- 'HEAD\.\.' scripts/`
give the whole population of candidates:

- `scripts/lib/resolve.sh:2254` —
  `git -C "$store" log --format='%s' "HEAD..$second"`, inside
  `gitlore_merge_commit_message`. The only `HEAD..` anywhere under `scripts/`.
- `scripts/lib/resolve.sh:2160` — `log --format='%s' "$old_gitlink..HEAD"`. Argv
  is `… log --format=%s <sha>..HEAD`, which cannot match a pattern anchored on
  `HEAD..`, and it runs only after a landed commit.
- `scripts/cc-hooks/memory-commit-batch.sh:114` — `log -1 --format='%h %s'`; no
  match, and not in this run's path.

So the original `case " $* " in *" log --format=%s HEAD.."*)` had no false match
today. It was still loose in two ways, both **fixed**: the pattern was
unanchored on the right, so any future call beginning `HEAD..` would also match,
and it did not pin *which* merge's range was logged. The stub is now keyed on
the concrete second parent, captured before the run:

```
  second=$(git -C memory/ddaanet rev-parse MERGE_HEAD)
…
  *" log --format=%s HEAD..$second "*) echo "\$*" >> "$log_hits"; exit 1 ;;
```

The wrapping spaces of `" $* "` close the pattern on both sides, and the
revision range is the invocation's last argument, so the match is now argv-exact
rather than a prefix.

`exec`ing the real git for everything else does not mask a second failure. If
any earlier git call failed, the script would exit before the message build,
`$log_hits` would be empty and the `grep -qF` would fail — it is asserted ahead
of the wording line precisely so a wrong-cause exit 1 does not read as the
intended red. That is also why `[ -s "$log_hits" ]` was **removed**: the stub
writes the file only when it matched, so the two assertions tested the same
condition and the weaker one added nothing.

**On durability.** The coupling to that argv is real and cannot be removed — an
error injection has to name a command. It is not fragile, though, because it
fails loudly: a reimplementation of `gitlore_merge_commit_message` that stops
logging the range leaves nothing to fail the build, the continuation lands the
merge, and `[ "$status" -eq 1 ]` fails. What is *pinned* is the build failing
and the state it leaves; the argv is only the lever. The test's comment now says
so, so a future reader knows to re-point the stub rather than delete the test:

> Fail the message build, which lists the subjects the merge brings in from its
> second parent. The stub is keyed on that revision range, so no other git call
> in the run can match it, and every other invocation reaches the real binary.
> The build is coupled to this argv by the stub alone: were it to stop logging
> the range, nothing would fail the build and the status assertion below would
> catch the run landing the merge instead.

## 4. Ordering

No ordering assertion is added, and one would be vacuous here. Slice 1's glob is
meaningful because the `commit-msg` hook writes `commit refused by hook` to
stderr, so there are two lines to order. The build's own failure is the stub's
bare `exit 1`: it prints nothing, and `sed` downstream of the failed `git log`
is silent too, so the build line is the only text about the failure on stderr.

What *is* worth discriminating is the arm, which the original test did not
check. Added, with the reason inline:

```
  # The build arm, not the refused-commit arm, which the run never reaches.
  # No ordering glob pairs with it: the build's own failure is the stub's
  # silent `exit 1`, so there is no git reason on stderr for it to follow.
  [[ "$stderr" != *"the merge commit was refused"* ]]
```

This kills a GREEN that routes both failures through one shared message, or that
emits both lines.

## 5. State after the run — three invariants were missing

The delivered test pinned `MERGE_HEAD` and the absent message file. It did not
pin the merge state, the staged synthesis, or that the merge is still landable —
so a change that removed `MERGE_HEAD`'s siblings, or reset the index, or
abandoned the preparation, would have passed. Added, matching slice 1:

```
  [ -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]
  [ -n "$(git -C memory/ddaanet diff --cached --name-only -- MEMORY.md)" ]
  [ -n "$(git -C memory diff --cached --name-only -- MEMORY.md)" ]
…
  # Prepared, not abandoned: with the stub gone the continuation lands.
  rm -f "$fakebin/git"
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
```

The two staged-content checks are the pair `compose_merged_indexes` leaves
behind before the commit: `add -A` in the merged tier and `add -- MEMORY.md` in
the memory root. The rerun is what makes the test name's "keeps the merge
prepared" an assertion rather than a claim, and it is the direct analogue of
slice 1's hook removal and rerun. All five pass under the probe.

`rm -f "$fakebin/git"` rather than restoring `PATH`: a variable assignment
prefixed to a shell function is not reliably scoped to the call in bash, so the
stub is removed instead of trusting `PATH` to have been restored. A stale
directory on `PATH` is harmless.

## 6. Hygiene

- `$TMPDIR` / `$BATS_TEST_TMPDIR` split matches the sibling exactly: `TMPDIR`
  exported to `$BATS_TEST_TMPDIR/msgtmp` so the script's `mktemp` lands
  somewhere the test can sweep, with `fakebin` and `log-hits` kept under
  `$BATS_TEST_TMPDIR` rather than the redirected `$TMPDIR`.
- Stub shape follows `tests/merge_memory.bats`: `case " $* "`,
  `exec "$real_git" "$@"`, `$real_git` resolved before the stub goes on `PATH`,
  `PATH` prefixed only on the `run` line.
- Whitespace safety: every interpolated path in the heredoc lands inside double
  quotes in the generated script (`"$real_git"`, `>> "$log_hits"`), and every
  command substitution in the assertions is quoted. `find … -print -quit` and
  `grep -qF --` rather than a glob or an unguarded pattern.
- bash 3.2 / BSD: no `mapfile`, no associative arrays, no GNU-only flags;
  `find -print -quit` and `wc`-free counting.
- No line numbers, plan ids or `plans/` references in comments.
- Test name is accurate on all three claims it makes — no message file, merge
  prepared (now proven by the rerun), and the build failure as the cause.

Nothing UNFIXABLE. Nothing committed; `scripts/` is clean and the only working
tree change is `tests/resolve_compose.bats`.
