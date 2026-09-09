# Item 4.0 — narrow the per-batch baseline invariant to per-agent

Scope: `docs/references/index-authoring-sync.md` only. Uncommitted, unstaged. No
`D<n>` added or renumbered; the heading still reads D38–D40, D47, D48.

## Replacement 1 — the baseline invariant (D38, second paragraph)

Replaced:

> …so every baseline is per-batch.

with a per-(agent, batch) statement plus the mechanism: the stash name carries
the payload's `agent_id`, which hook stdin sets only inside a subagent, so the
main thread keeps the unsuffixed name and a batch resolves only what its own
agent stashed.

Replaced:

> the post-hook drops the stash at every batch end, even one where the index
> went untouched, so a pre-image can never become a *second* batch's baseline. A
> stash stranded by an interrupted batch is consumed rather than discarded: the
> difference between it and the file is a propagation still owed.

with: the drop still happens at every batch end including an untouched one, but
what it buys is that a pre-image can never become *another agent's* baseline — a
parent batch ending mid-subagent consumes its own and leaves the subagent's edit
standing; a stash stranded by an interrupted batch is consumed by that same
agent's next batch; one left by a subagent that died mid-batch is consumed by
nothing, and since an agent id is not reused the residual is one file per dead
subagent rather than unbounded growth, a bound stated in a comment rather than
swept.

Added one sentence: the compose hook's pre-batch stamp is its own file, keyed
and dropped the same way, so neither hook depends on running before the other.

Re-wrapped the paragraph's last three lines (`PreToolBatch` sentence) so the
greedy 80-column fill is unbroken after the insertion.

Code the new claims rest on:

- `scripts/lib/index-sync.sh:92-109` — `gitlore_index_preimage_file` and
  `gitlore_compose_stamp_file` append `_gitlore_agent_suffix "$agent_id"`;
  absent/empty yields the unsuffixed name, "so the main thread's files do not
  migrate". The stamp's own comment states the independent-ownership reason.
- `scripts/cc-hooks/index-sync-pre.sh:40-64` — reads `.agent_id`, resolves both
  keyed names, and its comment carries the two claims verbatim: "a parent batch
  ending mid-subagent consumes and removes its own bare pair only", and the
  residual — "a subagent that dies mid-batch leaves its keyed files behind … An
  agent id is not reused, so the leftovers are one pair per dead subagent, not
  unbounded growth".
- `scripts/cc-hooks/index-sync-post.sh:26-52` — keys on `agent_id` ("never
  `agent_type`"), bails when its own keyed baseline is absent, and `rm -f`s it
  on the byte-identical path: "This bounds a stale pre-image to a single batch
  of the agent that owns it — the only agent that ever resolves this name."
- `scripts/cc-hooks/index-compose.sh:36-63` and
  `scripts/cc-hooks/add-tier-batch.sh:66,89` — the other two consumers resolve
  and drop the same keyed stamp, which is what makes the drop bound only its own
  agent.

The item's line citation is the only discrepancy found, and it is the one the
dispatch already corrected: the file is `scripts/cc-hooks/index-sync-pre.sh`,
not `scripts/lib/`, and the sentence sits at `:47-58`. The code says what the
item said it says.

## Replacement 2 — the reporting paragraph (D38, "reports on both channels")

Swept and found falsified: the paragraph asserts the user gets one line and the
agent gets the full `old → new` list, which is untrue when the actor is a
subagent — both channels are then confined to that subagent's transcript.

Added a following paragraph: inside a subagent both channels reach that
subagent's own transcript and nothing else (measured under CC 2.1.261), so a
keyed run also stages the two bodies in a relay marker named with the same
`agent_id`; the next parent-side run — one with no agent id — folds every marker
into its own report, frames each block with the agent that staged it, and
removes them, and `session-start.sh` drains the same way so a marker outliving
its session still lands. Stated as in addition to the subagent's own emission,
not instead of it. Closing distinction: the marker shares the pre-image's key
and not its consumer — a baseline is consumed by the agent that took it, a
report by the side that can show it.

Code the new claims rest on:

- `scripts/lib/index-sync.sh:111-122` — `gitlore_relay_marker_file`, keyed by
  the same suffix, with the confinement measurement (CC 2.1.261) and the "staged
  here for the next parent-side run to fold in and remove" contract.
- `scripts/lib/index-sync.sh:156-161` (`gitlore_relay_write`) — refuses an empty
  agent id, so only a keyed run stages.
- `gitlore_relay_drain` in the same file — enumerates `gitlore-relay-*` only,
  frames each block with the agent id from the filename suffix, sorts
  `LC_ALL=C`, and removes each marker.
- `scripts/cc-hooks/index-sync-post.sh:255-292` and
  `scripts/cc-hooks/index-compose.sh:66-104` — write when `agent_id` is set,
  drain when it is not, and both comments state "in addition to, not instead of,
  the emission below: the subagent is the actor and gets its own copy too".
- `scripts/cc-hooks/session-start.sh:398` — `gitlore_relay_drain "$mempath"`.

## Rest of the node — swept, nothing else falsified

- D38 §1 (per-line keying, added/changed/unchanged) — unaffected by keying.
- D38 "consumes the stash **unconditionally** … the next post-hook diffing a
  fresh index against an ancient baseline" (`index-sync-post.sh:129-132`) —
  still true; "the next post-hook" is now that agent's next, which the new
  invariant paragraph already establishes, so the sentence stands unedited.
- D39 — the two advisories are diff-keyed to the pre-image, and "only lines this
  batch added or changed" holds unchanged under per-agent keying. The budget
  nudge is keyed by `session_id`, not by agent (`index-sync-post.sh`
  `gitlore_index_budget_nudge_file "$mempath" "$session"`), and the node makes
  no once-per-episode claim to narrow.
- D40, D47, D48 and Rejected alternatives — no claim touches the baseline
  lifecycle or the report's destination.

## Checks

- `python3 scripts/check-docs-links.py` — exit 0; all nine counters zero
  (`broken-link`, `unstubbed-decision`, `stub-without-body`,
  `duplicate-decision`, `duplicate-conclusion`, `undefined-decision`,
  `enumeration-drift`, `delegation-drift`, `oversized-file`). 49 decisions, 111
  files scanned.
- Wrap: every line of the file is ≤ 80 characters (verified counting characters,
  not bytes — the em dashes make a byte count read 81-84 on pre-existing lines).
  A greedy 80-column refill simulation over the file reproduces both edited
  paragraphs exactly; the six paragraphs it does not reproduce are all
  pre-existing and untouched.
- File length 311 lines, against the 400-line cap.
- Not run, per dispatch: `just precommit`, `lint`, `test-unit`,
  `test-integration`, `format-docs`. Nothing committed or staged.
