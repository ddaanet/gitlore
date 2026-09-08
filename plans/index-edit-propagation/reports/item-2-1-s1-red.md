# Item 2.1 slice 1 — RED report

Scope: `tests/index_sync.bats` only, section "per-agent pre-image /
compose-stamp paths" (added after the `hooks.json` registration e2e test, before
the routing-key advisories section).

Command run:

```
bats -f "preimage_file|compose_stamp_file" tests/index_sync.bats
```

Output:

```
1..4
ok 1 preimage_file is unsuffixed with no agent id
not ok 2 preimage_file suffixes the agent id
# (in test file tests/index_sync.bats, line 629)
#   `[[ "$output" == *gitlore-index-preimage-agent-7 ]]' failed
ok 3 compose_stamp_file is unsuffixed with no agent id
not ok 4 compose_stamp_file suffixes the agent id
# (in test file tests/index_sync.bats, line 646)
#   `[[ "$output" == *gitlore-compose-stamp-agent-7 ]]' failed
```

## Per case

1. **`preimage_file is unsuffixed with no agent id`** — PASS, by construction.
   Asserts `gitlore_index_preimage_file memory` and
   `gitlore_index_preimage_file memory ""` both end in `gitlore-index-preimage`.
   Today's `gitlore_index_preimage_file` takes only `$1` and ignores a second
   argument entirely, so both calls already return the unsuffixed path. Not a
   red case; reported as expected pass per the dispatch instructions.

2. **`preimage_file suffixes the agent id`** — RED, failed assertion.
   `run gitlore_index_preimage_file memory agent-7` then
   `[[ "$output" == *gitlore-index-preimage-agent-7 ]]` — died on that line
   (`tests/index_sync.bats:629`). The function ignores the second argument, so
   `$output` is the plain `.../gitlore-index-preimage`, which does not match the
   `*-agent-7` suffix pattern. This is a failed assertion against a value that
   ran cleanly, not a missing-symbol or syntax error.

3. **`compose_stamp_file is unsuffixed with no agent id`** — PASS, by
   construction, same reasoning as case 1 applied to
   `gitlore_compose_stamp_file`.

4. **`compose_stamp_file suffixes the agent id`** — RED, failed assertion.
   `run gitlore_compose_stamp_file memory agent-7` then
   `[[ "$output" == *gitlore-compose-stamp-agent-7 ]]` — died on that line
   (`tests/index_sync.bats:646`), same cause as case 2:
   `gitlore_compose_stamp_file` ignores its second argument today.

Nothing under `scripts/` was touched. Nothing committed.

Superseded by test review: the four assertions were strengthened from trailing
globs to equalities against `rev-parse --git-path`, so the line numbers and
assertion text quoted above are the RED run's, not the tree's. The slice's shape
is unchanged — see `item-2-1-s1-test-review.md` for the re-run.
