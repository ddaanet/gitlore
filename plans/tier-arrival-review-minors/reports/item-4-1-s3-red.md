# Item 4.1, slice 3 — RED

New test in `tests/resolve_compose.bats:478-519`, inserted between the
message-build-failure test (slice 2) and "a duplicate in the merged root index
keeps the merge unlanded". `shellcheck -x tests/resolve_compose.bats` is clean.

## Test text

```bash
@test "a failed mktemp for the merge message file leaves the merge prepared" {
  prepare_tier_merge_with_new_lines
  mkdir "$BATS_TEST_TMPDIR/msgtmp"
  export TMPDIR="$BATS_TEST_TMPDIR/msgtmp"
  # A stub, not a missing TMPDIR: gitlore_git and the composition helpers take
  # mktemp under this same TMPDIR well before :309, so pointing it at a
  # missing directory would kill the run elsewhere. The stub is keyed on the
  # merge-msg template, so only that call fails and every other mktemp reaches
  # the real binary.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_mktemp=$(command -v mktemp)
  log_hits="$BATS_TEST_TMPDIR/mktemp-hits"
  : > "$log_hits"
  cat > "$fakebin/mktemp" <<EOF
#!/bin/sh
case " \$* " in
  *" ${TMPDIR}/gitlore-merge-msg.XXXXXX "*)
    echo "\$*" >> "$log_hits"
    echo "mktemp: failed to create file via template '${TMPDIR}/gitlore-merge-msg.XXXXXX'" >&2
    exit 1
    ;;
esac
exec "$real_mktemp" "\$@"
EOF
  chmod +x "$fakebin/mktemp"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  # The targeted call is the one that failed, not some other mktemp the stub
  # forwarded.
  grep -qF -- "${TMPDIR}/gitlore-merge-msg.XXXXXX" "$log_hits"
  [[ "$stderr" == *"gitlore: the merge message file could not be created, so the merge was not committed; the merge stays prepared."* ]]
  # Neither sibling arm: both sit below this one and the run never reaches them.
  [[ "$stderr" != *"the merge message could not be built"* ]]
  [[ "$stderr" != *"the merge commit was refused"* ]]
  git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD >/dev/null
  [ -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]
  [ -n "$(git -C memory/ddaanet diff --cached --name-only -- MEMORY.md)" ]
  [ -n "$(git -C memory diff --cached --name-only -- MEMORY.md)" ]
  [ -z "$(find "$TMPDIR" -name 'gitlore-merge-msg.*' -print -quit)" ]
}
```

## RED run

`scripts/run-bats.sh tests/resolve_compose.bats --filter "a failed mktemp for the merge message file leaves the merge prepared"`
and, separately, the full file. Both give the same `not ok` block:

```
not ok 15 a failed mktemp for the merge message file leaves the merge prepared
# (in test file tests/resolve_compose.bats, line 510)
#   `[[ "$stderr" == *"gitlore: the merge message file could not be created, so the merge was not committed; the merge stays prepared."* ]]' failed
# gitlore: memory merge prepared (flavor=head-vs-remote) in store:
# gitlore:   /tmp/claude-1000/gitlore-test.4Qjnwq/memory/ddaanet
# gitlore: dispatch sub-agent gitlore:memory-merger with state file:
# gitlore:   /tmp/claude-1000/gitlore-test.4Qjnwq/.git/modules/gitlore-memory/modules/ddaanet/gitlore-merge-state
# gitlore: that dispatch is a required step of the git operation that triggered
# gitlore: this merge, not an option: the request for that operation is the
# gitlore: request for this dispatch, so make it now without asking first. Review
# gitlore: the synthesis it returns yourself — both sides of this merge already
# gitlore: passed an approval gate, so do not prompt the user (D49).
# gitlore: on approval of its synthesis, the sub-agent must run:
# gitlore:   cd "/tmp/claude-1000/gitlore-test.4Qjnwq" && bash "/Users/david/code/gitlore/tests/../scripts/resolve.sh" continue-after-merge

bats: 24 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.jN6YtC
```

The trailing `gitlore: memory merge prepared …` block is not the run under test
— it is `prepare_tier_merge_with_new_lines`' own `bash "$preparer"` call (the
pre-push hook that prepares the merge), invoked outside `run` so its stderr goes
straight to the test's own output; bats echoes a failing test's full output,
which is why it appears in the diagnostic. It predates the `RESOLVE` invocation
and has no bearing on `$stderr`.

The reported failure is on **line 510**, the message-file line's own assertion —
the intended red. Line 506 (`status -eq 1`) and line 509 (the hit-file grep) are
not cited as failing, which is bats' proof they passed: `scripts/resolve.sh:309`
is a bare `mktemp` assignment under `errexit`, so the stub's forced failure
aborts the run at exit 1 immediately, before any `gitlore:` line is printed —
matching both assertions, and leaving the new message-file assertion (510) as
the first (and only) one to fail.

## Full-suite run

`scripts/run-bats.sh tests/resolve_compose.bats` (no filter):
`24 passed, 1 failed` — the new test is the sole failure; every other test in
the file still passes.

## Scope

Only `tests/resolve_compose.bats` changed. `scripts/resolve.sh` and every other
production file are untouched. Nothing committed; the new test sits uncommitted
in the tree.
