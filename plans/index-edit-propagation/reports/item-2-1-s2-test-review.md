# Item 2.1 slice 2 — test review

Scope reviewed: the three new cases in `tests/index_sync.bats` and the
`batch_payload` / `pre_stdin` helper changes, against
`plans/index-edit-propagation/reports/item-2-1-s2-red.md`. Read-only for
judgement: `scripts/lib/index-sync.sh`, `scripts/cc-hooks/index-sync-pre.sh`,
`plans/index-edit-propagation/outline.md` §C, slice 1's test and code reviews,
and the recall artifact's memory entries.

Two changes applied, both inside this slice's own cases, both closing a
wrong-reason-pass channel the design names explicitly. The slice is still red in
the same shape.

## Mechanical verdict per case

Reproduced the RED report's run verbatim before touching anything — byte
identical, including the cited line 148:

```
$ bats -f "stamps the keyed path|stamps the bare path|cannot leave the gitdir" tests/index_sync.bats
1..3
not ok 1 pre: a payload carrying agent_id stamps the keyed path, not the bare one
# (in test file tests/index_sync.bats, line 148)
#   `[ -f "$(gitlore_index_preimage_file memory a1)" ]' failed
ok 2 pre: a payload with no agent_id stamps the bare path
ok 3 an agent id outside [A-Za-z0-9-] cannot leave the gitdir
```

1. **`pre: a payload carrying agent_id stamps the keyed path, not the bare one`
   — FAILED on its assertion.** `[ "$status" -eq 0 ]` on the preceding line
   held, so the hook was found, ran and exited 0; death is on the `-f` of the
   keyed pre-image, a value assertion, not an error and not a missing symbol.
   **Both halves are asserted**, as the RED report claims: the keyed pair (`-f`
   × 2) and the bare pair (`! -f` × 2). A bats test body runs under errexit, so
   GREEN cannot satisfy the case by flipping only one — the keyed `-f` aborts
   first if the keyed file is missing, and the bare `! -f` aborts if the hook
   keeps writing both. Confirmed by the mutation matrix below: the
   `.agent_id`-only hook satisfies all four, the reversed-precedence hook fails
   the first.
2. **`pre: a payload with no agent_id stamps the bare path` — passed, and is
   non-vacuous.** Detail under "Case 2's non-vacuity" below; it reds when the
   hook writes a keyed file alongside the bare one, and (after my fix) when the
   hook keys on `agent_type`.
3. **`an agent id outside [A-Za-z0-9-] cannot leave the gitdir` — passed on the
   committed tree, with real mutation evidence.** Reproduced the RED report's
   passthrough mutation independently and got its exact failure, then ran three
   further mutations in both widening directions. Detail under "Case 3's
   widening direction".

The SUT was restored byte-identical after every mutation; proof at the end.

## Findings

### Major — nothing ruled out a hook keying on `agent_type`

**Fixed.** Outline §C states the constraint in as many words: "Read `agent_id`
specifically, never `agent_type` — that one also appears on the main thread of
an `--agent` session", which `memory/ddaanet/hook-input-schema.md` confirms
(`agent_id` is subagent-only; `agent_type` also appears on the main thread of an
`--agent` session). Neither payload in the slice carried an `agent_type` at all,
so the field was invisible to every assertion and the forbidden reading was
green across the board. Measured, not read — a hook mutated to
`jq -r '(.agent_id // .agent_type) // empty'` and passed to the two helpers:

```
=== MG (forbidden GREEN: .agent_id // .agent_type) against the three cases AS WRITTEN ===
1..3
ok 1 pre: a payload carrying agent_id stamps the keyed path, not the bare one
ok 2 pre: a payload with no agent_id stamps the bare path
ok 3 an agent id outside [A-Za-z0-9-] cannot leave the gitdir
```

A GREEN that keys the main thread of an `--agent` session onto a per-agent path
— the exact regression §C's sentence exists to prevent — would have shipped with
a clean slice.

**Changed:** case 2's payload gains `agent_type:"general-purpose"` while still
carrying no `agent_id`. That is the real shape of a main-thread `--agent`
payload, so the fixture is more faithful, not merely stricter; case 2's title
and contract are unchanged. Case 1's payload gains `agent_type` too, with a
value distinct from its `agent_id`, because a real subagent payload carries both
and the pair is what makes a reversed reading (`.agent_type // .agent_id`) fail
on case 1's own assertions rather than only on case 2's. The section comment now
states the `agent_id`-not-`agent_type` rule and why case 2 carries the decoy
field, so the next reader cannot delete it as noise.

Both additions are inert under the correct implementation: with
`jq -r '.agent_id // empty'` all three cases pass (see the matrix).

### Assessed, no defect — case 2's non-vacuity

The `find` idiom does what the RED report claims, verified by mutation rather
than by reading. With the hook mutated to write `…-zz` keyed files
*in addition to* the bare ones (so the two `-f` positives still hold), case 2
reds on the `find`:

```
=== MH1: hook writes keyed files IN ADDITION to bare ===
not ok 1 pre: a payload with no agent_id stamps the bare path
# (in test file tests/index_sync.bats, line 173)
#   `[ -z "$(find "$(dirname "$(gitlore_index_preimage_file memory)")" \' failed
```

Supporting probes, run against the real fixture:

- `gitlore_index_preimage_file memory` returns an **absolute** path
  (`…/.git/modules/gitlore-memory/gitlore-index-preimage`), so `dirname` of it
  is the gitdir regardless of the test's cwd, and both helpers resolve to the
  same directory.
- `-name 'gitlore-index-preimage-*'` does **not** match the bare
  `gitlore-index-preimage` (probed with only the bare file present), so the
  negative is not self-defeating, and the compose glob does not match a keyed
  pre-image.
- BSD-safe order: path first, then `-maxdepth 1 -name`, with an explicit path
  argument (BSD `find` requires one; GNU defaults to `.`). There is no `find`
  stub in `tests/helpers/bsd-stubs.bash`, so this one is argued and inspected
  rather than machine-enforced — the invocation uses no GNU-only primary.
- **`find` did not error.** The directory exists because the `[ -f … ]`
  immediately above each `find` held, and a bats body is errexit'd. This
  matters: I confirmed that `[ -z "$(find /nonexistent … 2>/dev/null)" ]`
  **passes**, so a `find` over a missing directory is a live vacuity channel
  that the ordering — not the assertion — closes. Added a two-line comment
  recording that dependency, so a later edit that reorders the case cannot
  silently reopen it.

### Assessed, no defect — case 3's widening direction

Case 3 catches **both** directions. Four mutations of `_gitlore_agent_suffix`,
each applied in place and reverted:

| Mutation | Result |
| --- | --- |
| M1 `printf -- '-%s' "$1"` (the RED report's passthrough, no sanitizing) | red at `[ "$output" = "$base-$sanitized" ]` — matches the RED report's evidence exactly |
| M2 `tr -c 'A-Za-z0-9' '_'` (**over-aggressive**, collapses `-` too) | red at `[ "$output" = "$base-agent-7" ]` |
| M3 `tr -c 'A-Za-z0-9/-' '_'` (under-sanitizing, keeps `/`) | red at `[ "$output" = "$base-$sanitized" ]` |
| M4 `tr -c 'A-Za-z0-9.-' '_'` (under-sanitizing, keeps `.`) | red at `[ "$output" = "$base-$sanitized" ]` |

M2 is the one the dispatch asked about, and it dies on the `agent-7` passthrough
line specifically — the traversal id contains no `-`, so the traversal assertion
alone would not have caught it. The `agent-7` half is therefore load-bearing
rather than decorative, and the guard cannot silently widen.

Residual, stated rather than papered over: the expected traversal name is
re-derived test-side with the same `LC_ALL=C tr -c 'A-Za-z0-9-' '_'` the SUT
uses. No SUT mutation can move it (the `tr` runs in the test process, as M1–M4
show), but an editor who widens the SUT's character class and mechanically edits
the test's `tr` to match would keep the case green. The `agent-7` line is what
bounds that: any widening that touches `-` still reds. I did **not** add a
`dirname`-equality assertion for the title's "cannot leave the gitdir" claim —
with `$sanitized` containing no `/` by construction, it has no state of the
world in which it fails, and an assertion that cannot fail is the shape
`green-is-not-evidence` warns against.

### Assessed, no defect — `pre_stdin` needed no change

Verified rather than accepted. `pre_stdin() { printf '%s' "$1" | bash "$PRE"; }`
(`tests/index_sync.bats:109`) pipes its single argument through untouched and
constructs nothing, and both new cases build the whole payload — `agent_id`
included — with `jq -n` before calling it. There is nothing for an agent id to
change in the piper. Unmodified in the diff.

### Ships untested — `batch_payload`'s `TEST_AGENT_ID`

**Correct as written, and unexercised by this slice.** None of the three cases
drives the post hook, so the new field is dead code until slice 3 (and slice 4
reads the arm it selects). I exercised the helper's body directly to judge it
rather than reading it:

```
unset:  has("agent_id") -> false
empty:  has("agent_id") -> false     (TEST_AGENT_ID= )
set:    .agent_id       -> "a1"
spacey: .agent_id       -> "a 1"     (a space survives intact, no splitting)
```

So unset and empty both **omit the field entirely** — they do not emit
`"agent_id": ""` — which is the contract slice 4's assertions need, and it
mirrors `TEST_SESSION_ID`'s treatment. `--arg a "${TEST_AGENT_ID:-}"` and the
`if $a == "" then {} else {agent_id:$a} end` merge are whitespace-safe because
the value crosses into jq as an argument, never through word splitting. Stating
it plainly: **this helper ships with no test of its own in this slice**; its
first real exercise is slice 3's post-hook case, and if that slice does not
drive both arms the omission contract stays unpinned.

### Assessed, no defect — ambient environment and whitespace

- `CLAUDECODE`: neither new case reads it, and neither does `index-sync-pre.sh`
  (the only reference under `scripts/` is `lib/log.sh:10`, on a path these cases
  never reach). Ran the three cases under
  `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` and under `CLAUDECODE=1` —
  identical results both ways, so the outcome is not dispatch-only. This is the
  class `25ced81` fixed elsewhere; it does not recur here.
- Whitespace: every `$(…)` is inside double quotes, including the nested
  `find`/`dirname` composition, and `jq -n --arg` carries the paths. Proved
  rather than argued — re-ran the three cases with `TMPDIR` set to a directory
  containing a space and confirmed via a probe that the fixture really landed
  under `/…/space dir/gitlore-test.XXXXXX`, so the gitdir path the `find` and
  the `-f` tests received genuinely contained whitespace. Same 1-fail/2-pass
  result.
- bash 3.2: no arrays, no `${var^^}`, no `**`; the unmatched-glob hazard the
  slice text warns about is avoided by `find`, as specified.

### Minor — the RED report's line numbers are now stale

Not fixed: the RED report is out of scope for this dispatch (`plans/` other than
this file). For whoever reads it next — case 1's failing assertion moved from
`:148` to `:156`, and case 3's from `:709` to `:718`, purely from the two
comment/payload edits above. The assertion text is unchanged.

## Mutation matrix (final tests, three plausible GREENs)

Each mutation replaces the pre-hook's two baseline-path lines with an
`aid=$(jq -r '<expr>' <<<"$payload")` read passed to both helpers, then reverts.

| `<expr>` | case 1 | case 2 | case 3 |
| --- | --- | --- | --- |
| `.agent_id // empty` (correct) | ok | ok | ok |
| `(.agent_id // .agent_type) // empty` (falls back) | ok | **red** `:171` | ok |
| `(.agent_type // .agent_id) // empty` (reversed) | **red** `:156` | **red** `:171` | ok |

The first row matters as much as the other two: it proves the slice is
**satisfiable**, i.e. GREEN has a reachable target and the two fixes did not
over-specify the contract. The RED phase never established that.

Plus the SUT-level mutations already tabled: M1–M4 on `_gitlore_agent_suffix`
(case 3, both widening directions), and MH1 on the pre-hook (case 2's `find`).

## Re-run after the fixes

```
$ bats -f "stamps the keyed path|stamps the bare path|cannot leave the gitdir" tests/index_sync.bats
1..3
not ok 1 pre: a payload carrying agent_id stamps the keyed path, not the bare one
# (in test file tests/index_sync.bats, line 156)
#   `[ -f "$(gitlore_index_preimage_file memory a1)" ]' failed
ok 2 pre: a payload with no agent_id stamps the bare path
ok 3 an agent id outside [A-Za-z0-9-] cannot leave the gitdir
```

Same shape as the RED run: case 1 dies on its keyed-pre-image assertion with
`$status` already asserted 0, cases 2 and 3 pass, and case 3 still reds under
the passthrough mutation (M1 above, re-run after the fixes).

```
$ scripts/run-bats.sh tests/index_sync.bats
bats: 68 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.R1pvq1
```

The one failure is this slice's red case. No collateral damage — in particular
the `batch_payload` change leaves all the existing `post:` cases green, and the
helper is used in no other suite.

## Restore proof

Every mutation was applied in place and reverted with `git checkout -- <path>`.
After the last one:

```
$ sha256sum scripts/lib/index-sync.sh scripts/cc-hooks/index-sync-pre.sh
64f9d191243e685eda56bcb76456954306083bd22d21a6c087af1c8f65596c59  scripts/lib/index-sync.sh
36df81b75fcca71d2374e06d8f548ee74cfa6aee77c6b7e0bbfb848d916469fd  scripts/cc-hooks/index-sync-pre.sh
$ git status --porcelain -- scripts/
(no output)
```

`64f9d19…` is the sha the RED report recorded and the sha of the file before my
first mutation; `36df81b…` likewise for the pre-hook, which the RED report did
not touch and which I mutated only for the discrimination checks. Both files are
byte-identical to HEAD.

## Checks that passed, by name

- `bats -f "stamps the keyed path|stamps the bare path|cannot leave the gitdir" tests/index_sync.bats`
  before any edit — reproduced the RED report byte for byte, line 148 included.
- The same command after the fixes — 1 assertion failure (case 1), 2 passes.
- The same command under `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` and under
  `CLAUDECODE=1` — identical both ways.
- The same command with `TMPDIR` pointing at a space-bearing directory, plus a
  throwaway probe confirming the fixture really landed there — identical.
- `scripts/run-bats.sh tests/index_sync.bats` — 68 passed, 1 failed.
- M1–M4 on `_gitlore_agent_suffix` — case 3 reds under all four, on the expected
  line in each direction.
- MH1 on `index-sync-pre.sh` (keyed files written alongside bare) — case 2 reds
  on its `find`.
- The three-expression GREEN mutation matrix above — correct expression green on
  all three cases, both forbidden readings red.
- `find` vacuity probe — `[ -z "$(find /nonexistent …)" ]` passes, so the
  ordering dependency is real and is now documented in the case.
- `batch_payload` direct exercise — unset / empty omit `agent_id`, non-empty
  sets it, a spaced value survives.
- `shellcheck -s bash tests/index_sync.bats` — exit 0.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean`, same count as slice
  1.
- `git status --porcelain -- tests/ scripts/ plans/` — `M tests/index_sync.bats`
  and the two untracked report files only. No throwaway fixture left in
  `tests/`.

## Out of scope, untouched

- `scripts/lib/index-sync.sh` and `scripts/cc-hooks/index-sync-pre.sh` — mutated
  for discrimination only, restored byte-identical (proof above).
  `index-sync-pre.sh:43-47`'s now-falsified comment is GREEN's to rewrite.
- Slices 3 and 4's cases; `tests/cc_hook_index_compose.bats`;
  `tests/cc_hook_add_tier.bats`.
- `docs/`, `memory/`, and everything under `plans/` other than this report —
  including the RED report, whose stale line numbers are flagged above rather
  than edited.

Nothing committed. `just precommit` not run, per the dispatch.
