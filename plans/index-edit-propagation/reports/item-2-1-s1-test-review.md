# Item 2.1 slice 1 — test review

Scope reviewed: the four new cases in `tests/index_sync.bats`, section
`# --- per-agent pre-image / compose-stamp paths ---` (now lines 613–658), and
`plans/index-edit-propagation/reports/item-2-1-s1-red.md`.
`scripts/lib/index-sync.sh` read only, to judge the tests.

## Mechanical check — verdict per case

Reproduced the RED report's run verbatim before touching anything:

```
$ bats -f "preimage_file|compose_stamp_file" tests/index_sync.bats
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

Byte-identical to the RED report, including the two cited line numbers.

1. `preimage_file is unsuffixed with no agent id` —
   **PASS, for the stated reason.** `gitlore_index_preimage_file`
   (`scripts/lib/index-sync.sh:94`) reads only `$1` and never mentions `$2`, so
   both the bare call and the `memory ""` call already return the unsuffixed
   path. The case is not vacuous: it asserts a value (see the discrimination
   check below), and both calls are asserted, not just the bare one.
2. `preimage_file suffixes the agent id` — **FAILED on its assertion.**
   `[ "$status" -eq 0 ]` on the preceding line passed, so the function was
   found, ran, and exited 0; the death is on the comparison of a cleanly
   produced value. Not a missing symbol, not a syntax fault, not an ERROR.
3. `compose_stamp_file is unsuffixed with no agent id` —
   **PASS, for the stated reason**, same argument applied to
   `gitlore_compose_stamp_file` (`:102`).
4. `compose_stamp_file suffixes the agent id` — **FAILED on its assertion**,
   same shape as case 2.

So the slice is red exactly where the dispatch said it would be, and the two
expected passes are expected passes rather than assertion-free stubs.

## Findings

### Major — the assertions did not pin the path to the memory gitdir

The whole point of both helpers is that the file lands
*inside the memory submodule's gitdir*, via `rev-parse --git-path`. A trailing
glob (`[[ "$output" == *gitlore-index-preimage ]]`) says nothing about where the
path is rooted: an implementation returning the bare relative name
`gitlore-index-preimage`, with the `git -C "$1" rev-parse` dropped, satisfies
all four cases. That is a live wrong-reason-pass channel for GREEN, which edits
these two functions.

**Changed:** each case now binds
`base=$(git -C memory rev-parse --git-path gitlore-index-preimage)` (resp.
`gitlore-compose-stamp`) and asserts `[ "$output" = "$base" ]` /
`[ "$output" = "$base-agent-7" ]`. The command substitution mirrors what the
suite's other cases already do to locate the stash
(`tests/index_sync.bats:119,130,153,…`), so it reuses the established idiom
rather than inventing a helper.

Equality does not over-specify. `git rev-parse --git-path` for a non-special
name is just `<gitdir>/<name>`, verified directly:

```
$ git -C "$d" rev-parse --git-path gitlore-index-preimage
.git/gitlore-index-preimage
$ git -C "$d" rev-parse --git-path gitlore-index-preimage-agent-7
.git/gitlore-index-preimage-agent-7
```

so both plausible GREEN spellings — compose the name then call `--git-path`, or
call `--git-path` then append — produce the same string and both satisfy the
equality.

### Assessed, no defect — the "no trailing hyphen" half

The dispatch flagged that a trailing glob might not discriminate a `-` appended
for an empty id. It does: `*gitlore-index-preimage` is anchored at the end of
the string, so `…/gitlore-index-preimage-` fails to match. The original
assertion was sound on that point; the equality now covers it by construction
regardless. Both calls (`memory` and `memory ""`) were asserted in the original
and still are.

### Assessed, no defect — partial or doubled suffix

`*gitlore-index-preimage-agent-7` requires the full literal at the end, so
`…-preimage-agent-7-agent-7` (doubled) and `…-preimageagent-7` (no separator)
both fail it. Confirmed by mutation below rather than by reading.

### Assessed, no defect — ambient environment

Neither case reads any environment variable; the section contains no
`CLAUDECODE`, no `CLAUDE_*`, and no conditional at all. Re-ran the four under
`env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` (this shell has `CLAUDECODE=1`)
and got the identical 2-pass/2-fail result, so the outcome is not dispatch-only.

### Assessed, no defect — portability and whitespace

No `sed`, `grep`, `mktemp` or `find` in the new cases, so there is no GNU-ism
for `tests/helpers/bsd-stubs.bash` to catch. Every expansion of `$output` and
`$base` is double-quoted, and `[ "$output" = "$base" ]` compares whole strings
with no word splitting — a gitdir path containing spaces compares correctly.
`base=` is a plain assignment from a quoted command substitution, so it is
whitespace-safe too, and bats runs each `@test` in its own subshell, so the
unlocalised `base` cannot leak between cases (the suite's existing `stash=` and
`abs=` assignments follow the same convention). `[[ ]]`/`[ ]` and `${2:+…}` are
bash 3.2 constructs.

### Assessed, no defect — placement and fixture reuse

All four call `make_parent_with_memory` (`tests/helpers/fixtures.bash:14`), the
suite's standard parent-plus-submodule fixture, and add no fixture of their own.
The section sits after the `e2e:` block and before
`# --- routing-key advisories ---`, which is where that suite already puts a
helper-plus-its-consumers group; slices 2–4 add hook-level cases for the same
feature, so keeping the block together there is right. No change made.

### Minor — a section comment recording the contract

Added a comment above the four cases stating the contract (absent/empty yields
today's name so the main thread's files do not migrate; non-empty appends
`-<agent_id>`) and why the assertions are equalities. Without it the next reader
sees four near-identical string comparisons and no statement of what they
defend.

### Minor — stale quotes in the RED report

The RED report quotes assertion text and line numbers 629/646 that my edit moved
to 638/657. Appended a four-line forward pointer at the end of that report
saying the assertions were strengthened and where the current run lives. The RED
run's own record is left intact.

## Discrimination check (mutation)

Reading cannot settle whether an assertion rejects a wrong implementation, so I
ran the two contracts against four stand-in implementations in a throwaway bats
file inside `tests/` (deleted immediately after; `ls` confirms it is gone, and
the lint run below sees 137 files, unchanged). The SUT was not touched.

```
1..7
ok 1 M3 good: unsuffixed contract holds
ok 2 M3 good: suffix contract holds
ok 3 M1 naive hyphen: unsuffixed contract must REJECT
ok 4 M1 naive hyphen: suffix contract accepts (as expected)
ok 5 M2 bare name: unsuffixed contract must REJECT
ok 6 M2 bare name: suffix contract must REJECT
ok 7 M4 doubled: suffix contract must REJECT
```

- M3 `--git-path "…${2:+-$2}"` — the intended implementation; both contracts
  hold, so the tests are satisfiable and GREEN has a reachable target.
- M1 `--git-path "…-$2"` — appends `-` for an empty id; the unsuffixed contract
  rejects it while the suffix contract accepts, which is the correct split.
- M2 `printf 'gitlore-index-preimage%s'` — no gitdir resolution; both contracts
  reject. This is the channel the original globs left open.
- M4 doubled suffix — the suffix contract rejects.

## Re-run after the fixes

```
$ bats -f "preimage_file|compose_stamp_file" tests/index_sync.bats
1..4
ok 1 preimage_file is unsuffixed with no agent id
not ok 2 preimage_file suffixes the agent id
# (in test file tests/index_sync.bats, line 638)
#   `[ "$output" = "$base-agent-7" ]' failed
ok 3 compose_stamp_file is unsuffixed with no agent id
not ok 4 compose_stamp_file suffixes the agent id
# (in test file tests/index_sync.bats, line 657)
#   `[ "$output" = "$base-agent-7" ]' failed
```

Same shape as the RED run: the two suffix cases fail on their assertion line
with `$status` already asserted 0, the two unsuffixed ones pass.

## Checks that passed, by name

- `bats -f "preimage_file|compose_stamp_file" tests/index_sync.bats` — before
  the fixes: reproduced the RED report byte-for-byte, including line numbers.
- The same command after the fixes: 2 expected passes, 2 assertion failures on
  the strengthened comparison lines.
- The same command under `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`:
  identical result, so no ambient-environment dependence.
- `scripts/run-bats.sh tests/index_sync.bats` — the whole suite: 64 passed, 2
  failed, the two failures being this slice's expected red. No collateral damage
  to the 62 pre-existing cases.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean` (the repo's own
  discovery, which lints `.bats`).
- `shellcheck -s bash tests/index_sync.bats` — exit 0.
- Mutation harness, 7/7, above.
- `git status --short -- tests/ plans/ scripts/` — `M tests/index_sync.bats` and
  the two report files only. Nothing under `scripts/` was touched; no throwaway
  fixture left in `tests/`.
- `git rev-parse --git-path` composition probe — `<gitdir>/<name>` for both the
  plain and the suffixed name, so the equality assertions do not constrain which
  spelling GREEN chooses.

## Out of scope, untouched

- `scripts/lib/index-sync.sh` and everything under `scripts/cc-hooks/` — GREEN's
  work; read only.
- Slices 2–4's cases and their fixture changes to `batch_payload`, `pre()` and
  `feed()`; `tests/cc_hook_index_compose.bats`; `tests/cc_hook_add_tier.bats`.
- `docs/`, `memory/`, and everything in `plans/` other than the two report files
  named above.
- An agent id carrying a space, a slash or a `..` component is not asserted.
  Slice 1's contract is only "empty/absent → today's name, non-empty → append",
  and the id reaches these helpers from the hook payload rather than from user
  text; if that hardening is wanted it belongs with the consumers in slices 2–4,
  not here. Flagged, not added.

Nothing committed. `just precommit` not run, per the dispatch.
