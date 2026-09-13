# Slice 3 — the relay redesign in the design docs

Eight files touched: six docs, one new changelog body, one word in a test.
Nothing committed, no branch touched, no formatter run, no script or library
edited. `scripts/check-docs-links.py` is clean.

## Per file

### `docs/references/index-authoring-sync.md` (314 → 373 lines)

The unheaded D38 paragraph beginning "Inside a subagent both channels reach…"
becomes a headed block, **The relay — D51's mechanism**, in six bolded lead-in
paragraphs:

1. the confinement and the write toward a report file, keeping the "in addition
   to, not instead of" clause and the pre-image-key contrast, plus the
   not-staged fallback on the subagent's own `additionalContext`;
2. **A report is a write-once file, never merged** — the
   `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>` name and each component, the
   parallel-hooks grounding quoted from `code.claude.com/docs/en/hooks`, the
   `<name>.tmp` build and `mv` install as a same-filesystem rename, the refusal
   of an occupied name with the POSIX-`mv`-into-a-directory reason, and the
   same-process same-second collision as a stated residual;
3. **One drainer** — `relay-drain.sh` as the only reader, and the two reasons it
   is its own hook (doubling under parallelism; a baseline the dispatching batch
   never sets), no baseline of its own, keyed run exits at once;
4. **It drains its own session only** — the parent's `session_id` in a
   subagent's payload, the `gitlore-relay-<S>-*` enumeration, the
   `--- gitlore-relay agent <A> ---` framing in `LC_ALL=C` filename order,
   removal of exactly what it read, why unique names make claiming unnecessary,
   and the `.tmp` exclusion with its never-folded residual;
5. **`SessionStart` drains the same session, then sweeps by age** — `compact`
   and `resume` keeping the id and firing no batch, the seven-day sweep
   including temps, the drain-rule-not-sweep-rule distinction, and the
   undeliverable-to-an-ended-session argument;
6. **Two residuals bound delivery** — the drain-then-emit window (narrowed by
   the payload parses, closed by nothing; claim-by-rename named and pointed at
   `cc-platform.md`), and the background-subagent delivery timing.

The header bullet list gains a final clause naming the relay as D51's mechanism.
The node ends at 373 lines, under the 400 cap; `oversized-file` is 0.

### `docs/references/cc-platform.md` (226 → 255 lines)

D51's measurement paragraph is untouched. A sentence after it records that the
same probe logged the subagent's stdin carrying the **parent's** `session_id`,
which is what lets a hook name the conversation its report is owed to. The
mechanism sentence now reads "writes its two bodies to a report file keyed by
session and agent, drained by a dedicated `PostToolBatch` hook" and enumerates
what `index-authoring-sync.md` holds. The header bullet for D51 says "relayed
through a file keyed by session and agent".

Four rejected alternatives added to the closing section, each argued in two to
four sentences and each citing D51: one shared marker per agent merged into; a
drain inside each reporting hook; claim-by-rename before reading; folding
another session's stranded reports at `SessionStart`. The three existing ones
are unchanged. They live here rather than in `index-authoring-sync.md` because
`docs/decisions.md` states that each *Rejected* line is argued in the section
closing **that group's** node, and D51 is in the harness-workarounds group.

### `docs/references/session.md` (381 → 388 lines)

Step 10 becomes "Drain this session's relay reports, then sweep by age": the
own-session fold, `compact`/`resume` keeping the id while firing no
`PostToolBatch`, the seven-day sweep across all sessions with temps included,
and a corrected early-exit clause — a resume or compaction of the same session
still collects what is waiting, while a fresh session after a repair leaves it
to the sweep. The retired text promised the marker was merely delayed to the
session after the repair, which own-session keying makes false.

### `docs/decisions.md`

D51's conclusion line is now "its report is a write-once file keyed by session
and agent, drained by a dedicated `PostToolBatch` hook". The harness group's
*Rejected* line gains the four names above, after the three it already carried.

### `docs/design.md`

The Claude Code hooks bullet names the relay drainer: "a `PostToolBatch` relay
drainer is the one consumer of the reports hooks write from inside a subagent,
whose own output reaches nobody else (D51)".

### `docs/references/configuration.md`

The gitdir state-file inventory gains the relay reports —
`gitlore-relay-<session>-<agent>-<epoch>-<pid>-<tag>`, one per staged report,
built at `<name>.tmp`, removed by the drain or by the seven-day sweep (D51) —
alongside `gitlore-nudged`, the merge-state file and `gitlore-tier-landing`.

### `docs/changelog.md` + `docs/changelog/2026-09-13-the-relay-is-one-file-per-report.md`

Index line at the top of the list, followed by a blank line, matching the three
2026-09-13 neighbours; the body is a new file, same shape as the two 2026-09-11
entries (`# <date> — <title> (D51)`, then prose). It records the defect
(parallel hooks racing the merge-write, the doubled drain, agent-only keying,
the baseline the dispatching batch never sets, no concurrent test), the new
shape, and the residuals. Before→after framing is confined to this file.

### `tests/plugin_distribution.bats`

Line 196: `D51 (revised):` → `D51:`. The only non-docs edit.

## Link check

```
check-docs-links: 51 decisions, 118 files scanned
  broken-link 0 · unstubbed-decision 0 · stub-without-body 0
  duplicate-decision 0 · duplicate-conclusion 0 · undefined-decision 0
  enumeration-drift 0 · delegation-drift 0 · oversized-file 0
```

No dangling link was reported, so nothing needed fixing.

## Grounding notes

Every mechanism claim is taken from `scripts/lib/index-sync.sh`,
`scripts/cc-hooks/relay-drain.sh`, `index-sync-post.sh`, `index-compose.sh`,
`session-start.sh` and `hooks/hooks.json`, not from the brief. Two items are
worth naming:

- **The failure numbers in the changelog entry** are the only claims not made
  from the code, which is correct for a changelog: they are the deliverable
  review's Layer 2 probe against the pre-change library — over 200 iterations,
  two concurrent writes for one agent merged both 112 times, lost a report 86
  times and tore a marker twice; two concurrent drains relayed the block twice
  144 times, framed an empty block 51 times and were correct 5 times. I dropped
  the review's "88 losses were reported to the subagent as a failed write, the
  rest silent" because 86 + 2 = 88 makes it ambiguous whether any loss was
  silent, and I could not settle it from the report.
- **`tests/index_sync.bats:944` misstates that measurement** as "86/200
  survivors for two concurrent writers". 86 is the loss count, not the survivor
  count — the review records 112 iterations in which both reports survived. One
  word in a comment, in a file this slice does not own; flagged rather than
  edited.

Nothing in `docs/` cites `plans/`, a slice id, a report or a line number; a
repo-wide grep over `docs/` for `plans/`, `slice` and `(revised)` returns only
pre-existing changelog titles and `design.md`'s own statement that plans live in
`plans/`.
