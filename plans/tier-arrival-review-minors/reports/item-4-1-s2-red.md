# Item 4.1/2 — RED

## Test added

`tests/resolve_compose.bats`, "a message build failure leaves no message file
behind and keeps the merge prepared", placed directly after slice 1's "a refused
merge commit leaves no message file behind and keeps the merge for a rerun".

`prepare_tier_merge_with_new_lines` sets up the tier merge as slice 1 does;
`TMPDIR` is set to a scratch dir under `$BATS_TEST_TMPDIR` the same way. A `git`
stub on `$fakebin`, `PATH`-prefixed only on the `run` line, matches
`case " $* " in *" log --format=%s HEAD.."*)`, appends the matched argv to a
`log_hits` file, and exits 1; every other invocation `exec`s the real `git`.

## Stub-hit proof

`grep -n "HEAD\.\." scripts/resolve.sh scripts/lib/resolve.sh` finds exactly one
call shaped `log --format=%s HEAD..` in the whole tree:
`scripts/lib/resolve.sh:2254`, inside `gitlore_merge_commit_message`, which
`scripts/resolve.sh:312` invokes before the commit. The other `--format=%s` call
(`scripts/lib/resolve.sh:2160`, `$old_gitlink..HEAD`) runs only after a landed
commit, in the bookkeeping step this test never reaches, and its argument order
doesn't match the stub's pattern regardless. The test asserts
`[ -s "$log_hits" ]` and `grep -qF -- 'log --format=%s HEAD..' "$log_hits"`
before the wording assertion, confirming the stub — not some other cause — is
what failed the build.

Because the script runs under `set -euo pipefail` (`scripts/resolve.sh:4`), the
stub's `exit 1` fails the `log | sed` pipeline inside
`gitlore_merge_commit_message`, which returns non-zero to the
`gitlore_merge_commit_message ... > "$merge_msgfile" || { rm -f "$merge_msgfile"; exit 1; }`
line at `scripts/resolve.sh:312-313`.

## Run

`scripts/run-bats.sh tests/resolve_compose.bats` (foreground, unpiped):

```
not ok 14 a message build failure leaves no message file behind and keeps the merge prepared
# (in test file tests/resolve_compose.bats, line 449)
#   `[[ "$stderr" == *"gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared."* ]]' failed

bats: 23 passed, 1 failed
```

23 passed, 1 failed, matching the expected count. The failure lands exactly on
the build-line wording assertion — the last assertion in the test. The preceding
assertions (`status -eq 1`, the stub-hit proof, `MERGE_HEAD` still verifiable,
no `gitlore-merge-msg.*` file left under `$TMPDIR`) all pass under the current,
unfixed script: `scripts/resolve.sh:312-313` already removes the message file
and exits 1 on a build failure, it just emits no `gitlore:` line first. Those
three are asserted ahead of the wording line as preconditions, per the
dispatch's red-evidence requirement, so this run demonstrates the test fails on
the one assertion GREEN will satisfy rather than on an unrelated state check.

## Scope held

No change to `scripts/resolve.sh`.
`shellcheck --shell=bash tests/resolve_compose.bats` is clean.
