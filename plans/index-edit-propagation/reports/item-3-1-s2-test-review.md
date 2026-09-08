# Item 3.1 slice 2 — test review

Three cases added, four existing assertions strengthened. The suite is back in
the intended red state: 92 passed, 7 failed, every failure on its own named
assertion.

Both questions the dispatch raised were real defects, and both were verified
against running code rather than by reading. The verification is a mutation
matrix: three candidate GREEN implementations, each landed in a scratch copy of
the tree (`scripts`, `tests`, `hooks` copied to a scratch root, so the working
tree's hooks were never touched) and each run against both whole suites.

| candidate GREEN | cases that fail |
|---|---|
| fold placed **after** the emission guard | 13, 14, 67 — the three added ones |
| fold correctly placed, keyed write uses a **raw body with no delimiters** | 14 only |
| fold before the guard, `gitlore_relay_write` for the write | none — both suites green |

Before the additions, the first two candidates shipped green on all four
original cases and on every case in slice 1.

## Question 1 — the named constraint was pinned by nothing

Confirmed. The runbook's binding constraint — "the fold must precede the
emission guard, or a parent-side run whose only report is a relayed one emits
nothing" — was unpinned, and a fold-after-the-guard GREEN passed all four cases
plus all of slice 1 (row 1 of the matrix, run before the additions: zero
`not ok`).

Both hooks guard emission on their own report (`index-compose.sh:68`,
`index-sync-post.sh:243`), and both landed cases gave the unkeyed hook a report
of its own — `recomposed tier pointers` and
`reset frontmatter to match MEMORY.md` are asserted in them, so the guard was
satisfied independently of the relay in every case.

**The empty-own-report state is reachable in both hooks**, so the case was added
to both rather than one. Reachability was measured, not inferred: instrumented
copies of each hook printing to stderr at the emission point, driven by the
fixtures below, both reported `PROBE-REACHED-GUARD sysmsg=[]`.

- **compose** — the fixture of the existing
  `an already-composed store reports nothing`: compose once, then a second index
  edit takes a fresh baseline and moves the index, so the hook runs past
  `[ -n "$index_touched$manifest_touched" ]` (`:64`) into
  `gitlore_compose_and_report` and composition finds nothing left to do.
- **index-sync** — the pre-image holds `- [A](a.md) — old hook` and the
  post-batch index `- [A](a.md) — new hook`, so `cmp -s` (`:42`) differs and the
  loop runs; `a.md` already carries `description: new hook`, so `old = "$hook"`
  at `:145` and nothing is news.

The sync case carries an extra assertion the compose one does not need, and it
is what makes the fixture honest: the description goes in **unquoted** and
`gitlore_set_frontmatter_description` (`:141`) normalizes it to
`description: "new hook"`. With an empty own-report there is no other
observable, so without it a fixture that exited upstream of the report path
would red identically and for the wrong reason.

Added:

- `an unkeyed compose run with no report of its own still emits the relay`
  (`tests/cc_hook_index_compose.bats`)
- `an unkeyed index-sync run with no report of its own still emits the relay`
  (`tests/index_sync.bats`)

Each asserts the hook's own report is **absent** from `systemMessage`, so the
emission can only be the relay's doing, then that the framing line, the relayed
sysmsg body and the relayed ctx body are present on their respective channels,
and that the marker is gone.

## Question 2 — the seam was uncovered, and the gap is a silent one

Confirmed uncovered, and the failure it lets through is silent in production.
Case 1 asserts only that the marker exists and that
`grep -qF 'recomposed tier pointers'` matches it; case 2 folds a marker written
by `gitlore_relay_write` itself. Nothing made the two halves agree on the
on-disk **format**. A GREEN whose keyed branch wrote the raw body —
`printf '%s\n' "$_s" > "$(gitlore_relay_marker_file …)"` — passed both cases
(row 2 of the matrix), while in production `gitlore_relay_drain`'s
`awk '/^--- gitlore-relay-sysmsg ---$/ { f=1; next } …'` never sets `f`, yields
an empty body, and hands the parent a framing line wrapped around nothing.

Added `an unkeyed compose run folds in a marker a keyed run wrote`: a real keyed
run writes the marker, a real unkeyed run folds it. The keyed run leaves the
store composed, so the unkeyed run has nothing of its own to say and
`recomposed tier pointers` appearing in the parent's `systemMessage` can only
have come out of the marker — which is what lets the case pin the seam without
depending on where in the report the relayed block lands. The
`additionalContext` half is pinned the same way, on the compose ctx's
`tier composition rewrote these indexes` text.

It is the only case in either suite that reds against row 2 of the matrix.

## Question 3 — mechanical check and wrong-reason hunt

**Every listed test failed on an assertion.** Confirmed, before and after the
additions: no `PASS`, no bats `ERROR`, no `command not found`. The pre-existing
four reproduce the RED report's failing lines verbatim (line numbers shifted by
the additions).

**The "already true today" assertions in cases 1 and 3 — one was non-vacuous,
one was not, and it has been fixed.**

- Case 1 (compose) asserted `recomposed tier pointers`, which is the report's
  own text: a GREEN suppressing the subagent's copy fails it. Non-vacuous as
  claimed. It reached that text through `run jq -e . <<<"$output"` and then
  matched the *pretty-printer's* `$output`, which works only because `jq -e .`
  echoes its input — an implicit dependency, now removed by extracting
  `.systemMessage` directly. `jq -r` fails on malformed output, so JSON validity
  and the field content are one assertion.
- Case 3 (index-sync) asserted `[[ "$output" == *"systemMessage"* ]]` — the JSON
  **key**, not the report. That survives a wiring that relays the report instead
  of emitting it and puts anything at all on the user's channel, which is
  exactly the regression shape the assertion exists to catch. Replaced with the
  report's own text, `reset frontmatter to match MEMORY.md`, extracted from
  `.systemMessage`.

**A second wrong-reason path, in cases 2 and 4.** Both matched the framing line
and the relayed body as substrings of the raw JSON object. The drain frames
*both* channels, so those matches are satisfied by a fold that reached
`additionalContext` and never `systemMessage` — the user's channel, which is the
one the relay exists to reach. Both now extract `.systemMessage` and
`.hookSpecificOutput.additionalContext` separately and assert on each.

**Case 4's fixture is honest.** Its `bash "$PRE"` payload carries `agent_type`
but no `agent_id`, so the pre-hook stashes under the bare name; the index then
moves from `old hook` to `new hook` against an `a.md` carrying `OLD`, so
`replaced` is non-empty and the hook reaches the emission guard with a report of
its own. The RED report's account of why it needs that ("a marker planted with
no such baseline would never even be looked at") is correct. Verified by the
matrix: it passes under all three candidate GREENs, i.e. it fails today for the
relay's absence and nothing else.

**Early exits.** No case reds or passes on one. Every unkeyed case asserts
something the hook can only emit past its guard; the two empty-own-report cases
are the ones where an early exit was a live risk, and both were measured to
reach the emission point (Question 1). The compose cases' `pre` +
`seed_root_fact` pairing is what carries them past `:46` and `:64`; the sync
cases' `bash "$PRE"` plus a real index change is what carries them past `:40`
and `:42`.

**Whitespace, quoting, portability.** Every expansion is quoted; no word
splitting, no unquoted globs, no `ls` pipeline, no array. `[[ … == *…* ]]`,
`printf`, `grep -qF`, `jq` and `bash 3.2`-safe parameter expansion only — no
GNU-only flag, no `mapfile`, no `${var,,}`, nothing
`tests/helpers/bsd-stubs.bash` shadows. `shellcheck -s bash` clean on both
files; `scripts/lint-shell.sh` 137 files clean.

**Fixture leakage.** None. Both suites take a fresh `mktemp -d` repo per case in
`setup()` and `rm -rf` it in `teardown()`; the added cases build their own store
(`make_parent_with_memory` / the compose suite's `setup`) and write only inside
it. Nothing is written to the memory gitdir that outlives the case.

**`run` vs bare calls under errexit.** The relay helpers are used here as
*fixture*, not as the SUT — slice 1 owns their return contracts and captures
their status explicitly. Every bare `gitlore_relay_write` is followed
immediately by `[ -f "$marker" ]`, so a silent failure cannot pass for a
success. Every SUT invocation goes through `run`.

**Equality vs trailing glob.** The one equality assertion added
(`[ "$output" = 'description: "new hook"' ]`) is an exact match, matching the
suite's existing `grep '^description:'` assertions. The rest are substring
matches on report prose, where equality would pin unrelated wording.

## What changed

`tests/cc_hook_index_compose.bats`

- `a keyed compose run writes a marker and still emits its own json` — the own-
  report assertion now goes through `jq -r '.systemMessage'`.
- `an unkeyed compose run folds in the marker and removes it` — split per
  channel; `additionalContext` now asserted.
- **new**
  `an unkeyed compose run with no report of its own still emits the relay`
- **new** `an unkeyed compose run folds in a marker a keyed run wrote`

`tests/index_sync.bats`

- `a keyed index-sync run writes its replacement report to a marker` — the
  `systemMessage`-key assertion replaced with the report's own text, through
  `jq -r`.
- `an unkeyed index-sync run folds in the marker` — split per channel;
  `additionalContext` now asserted.
- **new**
  `an unkeyed index-sync run with no report of its own still emits the relay`

`plans/index-edit-propagation/reports/item-3-1-s2-red.md` — updated to the
seven-case shape, since it enumerated four and stated line numbers the additions
moved.

Nothing outside the review scope was touched: no hook, no `scripts/lib/`, no
`docs/`, no `memory/`, no other suite. Nothing committed; the tree is dirty and
unstaged.

## Verbatim red for the added cases

```
not ok 13 an unkeyed compose run with no report of its own still emits the relay
# (in test file tests/cc_hook_index_compose.bats, line 297)
#   `[[ "$output" == *"gitlore-relay agent a1"* ]]' failed
not ok 14 an unkeyed compose run folds in a marker a keyed run wrote
# (in test file tests/cc_hook_index_compose.bats, line 324)
#   `[ -f "$marker" ]' failed
not ok 67 an unkeyed index-sync run with no report of its own still emits the relay
# (in test file tests/index_sync.bats, line 817)
#   `[[ "$output" == *"gitlore-relay agent a1"* ]]' failed
```

Case 14 reds on its fixture precondition — the marker a real keyed run must have
written — because the end-to-end shape cannot reach its seam assertion until the
write half exists. That is inherent to the case and not a weakness in it: the
seam assertion is what makes it the only case in either suite that reds against
a correctly-placed fold with a wrong marker format.

## Checks that passed, by name

- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/index_sync.bats` —
  92 passed, 7 failed; every failure on its own named assertion, no other case
  in either suite regressed.
- Reachability probe, both hooks — instrumented scratch copies confirm each
  added empty-own-report fixture reaches the emission guard with an empty report
  (`PROBE-REACHED-GUARD sysmsg=[]`).
- Mutation matrix, three candidate GREENs over both whole suites — fold-after-
  guard reds 13/14/67 and nothing else; raw marker format reds 14 and nothing
  else; the correct implementation is green on both suites entire.
- `shellcheck -s bash tests/cc_hook_index_compose.bats tests/index_sync.bats` —
  clean.
- `scripts/lint-shell.sh` — 137 files clean.
- `git status --porcelain` — only the two test files modified plus the two
  report files; every scratch tree, instrumented copy and probe suite removed.
