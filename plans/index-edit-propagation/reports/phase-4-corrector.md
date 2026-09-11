# Phase 4 checkpoint review — corrector report

Scope: the documentation surfaces written by Items 4.0, 4.1, 4.2 and 4.3
(`2fa5328`, `ba68af9`, `ac3735f`), plus the comment-only `D51` back-fill in
three scripts. Accuracy judged against `scripts/lib/resolve.sh`,
`scripts/lib/index-sync.sh`, `scripts/lib/index-compose.sh` and
`scripts/cc-hooks/*.sh` at HEAD. Nothing staged, nothing committed.

## Verdict

Phase 4 is accurate on every behavioural claim the checkpoint named, with three
exceptions found and fixed and three out-of-scope staleness defects flagged. The
citation boundary is clean. FR-C and FR-E are discharged.

## Findings by severity

### MAJOR — fixed

**1. `git-hooks-and-entry-points.md` `## Mechanism` contradicted its own D50 on
ordering.** Item 4.1 added the composition to step 4 of the `pre-commit` list,
but the tier sync is step 3 — so the list read "sync every dirty tier, then
compose", the exact inversion D50's body argues against ("composes … ahead of
`gitlore_sync_tiers_to_live`: composition writes carrier files inside the
tiers"). The code is unambiguous: `gitlore_sync_memory_to_live` calls
`gitlore_compose` and only then `gitlore_sync_tiers_to_live`.

Fixed line-neutrally (the node is at the 400/400 cap): step 3 is now
"**Compose the store, then sync every dirty tier**", step 4 names
`gitlore_sync_memory_to_live` as "what runs step 3" so the decomposition does
not read as two separate calls, and the D50 opening paragraph was tightened by
one line to pay for the one the list gained. File still measures 400.

**2. `index-authoring-sync.md` attributed cross-agent safety to the drop rather
than to the key.** Item 4.0 wrote "the post-hook drops the stash at every batch
end … so a pre-image can never become *another agent's* baseline". The drop
bounds a stash's *lifetime* to one batch; what bounds its *ownership* is the
keyed name — `index-sync-pre.sh`'s own comment says as much ("The baselines are
keyed per agent, so a parent batch ending mid-subagent consumes and removes its
own bare pair only"). As written, a reader would conclude the unkeyed code was
already safe.

Fixed: the drop now buys "a pre-image never outlives the batch that took it",
and the key is named as what keeps one that does outlive it from becoming
another agent's baseline.

**3. The changelog entry's residual sentence was self-contradictory.** It said a
subagent that dies mid-batch leaves a keyed pair "and the next batch of that
same agent id consumes and deletes it" and then that "the leftovers are one pair
per dead subagent" — both cannot hold, and the first is false for a dead agent,
which has no next batch. `index-authoring-sync.md` states the split correctly;
the changelog collapsed it.

Fixed: a pair stranded by an *interrupted batch* is consumed by that agent's
next batch; one left by a subagent that *died* is consumed by nothing, and the
bound is one pair per dead subagent. (The same conflation is in
`scripts/cc-hooks/index-sync-pre.sh`'s comment, which is out of scope — see
below. The boundedness claim itself holds either way: `_gitlore_agent_suffix`
keys the name, an agent id is not reused, and the drain removes relay markers
unconditionally, so only the pre-image/stamp pair can strand.)

### MINOR — fixed

**4. "The next parent-side run … folds every marker in" overstated the drain.**
Both hooks exit before the fold when the batch changed nothing:
`index-compose.sh` at `[ -n "$index_touched$manifest_touched" ] || exit 0`,
`index-sync-post.sh` at the `cmp -s` arm. So the drain happens on the next
parent-side run *whose own batch changed the index or the manifest*, and
`session-start.sh` is the backstop for everything else — which is what that
backstop is for, not merely a cross-session safety net. Fixed in
`index-authoring-sync.md`. The abbreviated forms in `cc-platform.md` (D51) and
the changelog entry were left as the summaries they are.

**5. `index-authoring-sync.md`'s relay paragraph cited the measurement but not
the decision.** `cc-platform.md` (D51) points at this node for the mechanism,
the three scripts now cite `D51`, and this node alone still said only "(measured
under CC 2.1.261)". Now `(D51, measured under CC 2.1.261)`. No enumeration
change: `enumeration-drift` derives from `**D<n> — …**` bodies, not citations,
and the checker stays green.

**6. "one test would say so" read as a unit test** in D50's silence argument,
where it means a shell `[ -n … ]` on the captured compose result. Now spelled.

**7. The `Shared body` enumeration omitted the tier sync** it now has to be
ordered against: `dirty/freshness gate → pin guard → compose (D50) → `add -A``
skipped `gitlore_sync_tiers_to_live` entirely. Added `→ tier sync (D42)` in the
one short line that had room, so the file stays at 400.

## Claims verified true against the scripts

Every item the checkpoint listed, plus the rest of the D50/D51 bodies:

- **Ordering.** `gitlore_sync_memory_to_live` runs stale-merge guard → dirty +
  freshness gate → per-tier stale-merge guard → `gitlore_compose_check_pins` →
  `gitlore_compose` → `gitlore_sync_tiers_to_live` → `add -A` → commit →
  `rm msgfile` → `push . HEAD:live`. The pin guard is an explicit call at the
  top level, not `gitlore_compose`'s rc-1 arm (`gitlore_compose` runs
  `check_pins` too, but the outer guard aborts first, so the inner one never
  refuses here).
- **Restamp asymmetry.** The rc-2 and unrecognised-status arms
  `touch "$msgfile"`; the pin abort and the rc-1 report do not. Correct in the
  node and in the changelog, including the reason (the pin abort writes
  nothing).
- **The pin abort names no remedy of its own.** All three branches of
  `gitlore_compose_check_pins` print their own — `/gitlore:resolve` mid-merge,
  inspect-and-stage for a tier ahead of its pin, `checkout --detach <pin>` plus
  `/gitlore:merge` for one moved sideways — and the abort points at "the remedy
  on each line above".
- **`gitlore_adopt_recovered_merge`** composes up (`gitlore_compose_up`), stages
  `MEMORY.md` and the tier together with a named-pair `add`, and returns after
  the report without staging when the up projection fails.
- **Dirty-only scope.** The compose sits inside `if [ "$dirty" = "1" ]`.
- **Keying.** `gitlore_index_preimage_file`, `gitlore_compose_stamp_file` and
  `gitlore_relay_marker_file` all append `_gitlore_agent_suffix "${2:-}"`, which
  returns empty for an absent or empty id and otherwise `-<id>` with everything
  outside `[A-Za-z0-9-]` collapsed to `_`. All five hooks read
  `jq -r '.agent_id // empty'`; `agent_type` appears in `scripts/` only in
  comments explaining why it is not read.
- **Relay.** `gitlore_relay_write` refuses an empty id, reads both channels
  before reopening the marker and appends per channel (merge, not truncate);
  `gitlore_relay_drain` globs `gitlore-relay-*` with `find -print0`, frames each
  block with the filename's agent id, sorts `LC_ALL=C`, `rm -f`s each marker and
  returns 0 on every path; `session-start.sh:398` drains before the final emit;
  both hooks stage in addition to their own emission, and the unkeyed fold in
  `index-compose.sh` is placed ahead of the emission guard so a parent batch
  whose only news is relayed still reports.
- **D51's measurement** matches the probe: zero `hook_*` attachments in the
  parent transcript, all four in the subagent's own JSONL, both channels normal
  in the no-subagent control, CC 2.1.261.
- **"`gitlore_compose` had three callers"** — `session-start.sh:326`,
  `index-compose.sh:66` and `add-tier-batch.sh:75` (the latter two via
  `gitlore_compose_and_report`); `resolve.sh:1027` is the fourth this job added.

## Coherence across the four surfaces

Hub, index, nodes and changelog now agree, and each says the thing its layer is
for: `docs/design.md` carries one clause with a `(D50)`; `docs/decisions.md`
carries one conclusion bullet per decision plus both D50 alternatives and the
D51 alternative by name on the group `*Rejected:*` lines; the nodes carry the
mechanism and the argument; the changelog carries the narrative and the two
required surfaces.

The one placement worth naming:
**D50's fourth paragraph documents `gitlore_adopt_recovered_merge`**, which
belongs topically to `merge-state-recovery.md`. It is the right *argument* (it
is the pin guard's invariant seen from the other side, and Item 1.3 had no doc
item of its own), but a reader reaching for merge recovery will not find it —
`merge-state-recovery.md` describes the four classifications and never mentions
the adoption at all, before or after Item 1.3. Left as it stands; adding a
cross-reference costs a line the node does not have.

## Citation boundary

Clean.
`grep -nE "plans/|memory/[a-z]|runbook|Item [0-9]|slice|Phase [0-9]|:[0-9]+|inbox/"`
over the six changed docs returns only `docs/design.md:15` ("Plans and specs
live in `plans/`", pre-existing and not a citation) and one false positive on a
`3:1` ratio. Over `scripts/`, only `check-memory-hygiene.py:39`, which names
`plans/` as a directory it *excludes* and is repo-local surface (D22). No line
numbers, no `memory/` paths, no runbook or slice identifiers anywhere under
`docs/` or `scripts/`.

## Writing conventions

Present tense and current truth throughout the nodes, the index and the hub.
Nothing is framed as a correction of a previous version — in particular the
rewritten `index-authoring-sync.md` passage states the per-(agent, batch)
invariant directly rather than as an amendment. The changelog entry's past tense
is the changelog's own register (what the hole was, what it now does), which is
the one place the convention exempts.

## Lifecycle audit

| object | created | removed | residual |
|---|---|---|---|
| index pre-image `gitlore-index-preimage[-<id>]` | `index-sync-pre.sh` `cp "$index" "$stash"`, only when absent | `index-sync-post.sh` at the `cmp -s` arm and again after the diff pass, both unconditional | one pair per subagent that dies mid-batch — bounded, ids are not reused |
| compose stamp `gitlore-compose-stamp[-<id>]` | `index-sync-pre.sh`, only when absent | `index-compose.sh` unconditionally after reading it, before the touched-check; `add-tier-batch.sh` after its direct recompose | same bound, same pair |
| relay marker `gitlore-relay-<id>` | `gitlore_relay_write`, keyed runs only, refused for an empty id | `gitlore_relay_drain` `rm -f` per marker, from `index-compose.sh`, `index-sync-post.sh` and `session-start.sh` | none on any success path |
| commit-message file | the agent, or `commit-memory.sh` | `rm -f "$msgfile"` after the blessed commit | restamped (`touch`) and kept on the rc-2 and unknown-status aborts — deliberate, so the approval survives the retry |
| commit-notified marker | `post-tool-use.sh` (once per dirty episode) | `rm -f "$(gitlore_commit_notified_file …)"` after the commit | none |
| merge state + `gitlore-merge-<artifact>` | `gitlore_prepare_merge` | `gitlore_clear_merge_state` (one remover for the state file and all three artifacts) on the continuation and on dead-merge disposal | none on success |
| `MERGE_HEAD` / `MERGE_MSG` | git, or `gitlore_restore_staged_merge` | the merge commit itself; explicit `rm -f` on the dead-merge path | none |
| staged content in the memory index | `add -A` in `gitlore_sync_memory_to_live`; the named pair in `gitlore_adopt_recovered_merge` | the blessed commit consumes the first | the adopted pair is staged without a commit by design (D43's degraded case) and rides the next approved commit |
| tier bookkeeping tmp msgfile | `mktemp` in `gitlore_commit_tier_bookkeeping` | `rm -f` on both the success and the commit-failure path | none |

Two bounded residuals beyond the ones above, both pre-existing and neither a
leak:

- A batch that deletes `MEMORY.md` after the pre-hook stamped strands the pair:
  both post hooks exit at `[ -e "$index" ]`. Consumed by the same agent's next
  batch once the index is back.
- A `SessionStart` that exits early on divergence or a failed fast-forward does
  not drain; the comment at that call site states the choice (a store awaiting
  `/gitlore:resolve` is not the moment to surface a subagent's report) and the
  marker survives to the session after the repair.

No success path leaves an object behind.

## Out of scope — flagged, not edited

**A. `docs/references/index-composition.md` D31 is now false.** "Composition
runs at three points" (SessionStart, `PostToolBatch`, the merge continuation) —
the commit path is a fourth. Two sentences in that node need it:

- D31, first line of the body: "Composition runs at three points."
- D31, on the off-pin rule: "That last rule guards the down projection alone
  (D36), so it lives outside the shared check and
  **only the in-session pass runs it**" — `gitlore_sync_memory_to_live` calls
  `gitlore_compose_check_pins` directly, and `gitlore_compose` runs it on the
  commit path too.

D36's "Down, in-session, on `PostToolBatch` and at `SessionStart`" is the same
omission one layer down. The node is 310 lines, so there is room. This is the
last place the shipped design record still describes the pre-D50 trigger set.

**B. `docs/references/session.md` step list has no relay drain.** Steps 1–10
enumerate what `SessionStart` does; Phase 3 added `gitlore_relay_drain` between
the compose and the final emit, and it is user-visible (it appends to
`systemMessage` and `additionalContext`). A step between 9 and 10 would close it
— "**Drain the relay markers.** Fold in any report a subagent's `PostToolBatch`
hook staged that no parent-side batch collected, framed with the agent that
staged it (D51); skipped on the divergence and fast-forward-failure exits above,
where the marker is delayed rather than lost." The node is 375/400, so it fits.

**C. `scripts/cc-hooks/index-sync-pre.sh`'s residual comment carries finding 3's
conflation** — "a subagent that dies mid-batch leaves its keyed files behind,
and the next batch of that same agent id consumes and deletes them" followed by
"the leftovers are one pair per dead subagent". Script, out of scope, and the
bound it states is correct; only the mechanism sentence is muddled.

**D. `docs/references/configuration.md`** lists gitdir-resident hook state as
"the once-per-episode nudge marker `gitlore-nudged` and the merge-state file",
which predates the pre-image and the compose stamp and now also omits the relay
marker. It asserts no count, so nothing is falsified — it is just partial. Low
priority.

## Unfixable in scope

None. `git-hooks-and-entry-points.md` was at 400/400 and every fix it needed was
paid for in-file; it measures 400 after `just format-docs`. The node remains in
the state the Item 4.1+4.2 report flagged: at the cap, where the next line added
anywhere blocks the build and reads as a tooling failure. Splitting it is my
human partner's call and is not made here.

## Requirements coverage

- **FR-C** (parent and subagent batches never consume each other's index
  baselines) — the documentation half is discharged by Item 4.0. The node now
  states the per-(agent, batch) key, what the key buys versus what the drop buys
  (after finding 2), the stamp's independent ownership, and the bounded
  residual.
- **FR-E** (the design record carries the commit-path composition decision) —
  discharged. D50 is argued once in `git-hooks-and-entry-points.md` with both
  rejected alternatives, concluded once in `docs/decisions.md`, summarized in
  one clause of `docs/design.md`, and carried on both required changelog
  surfaces. D51 is a legitimate addition beyond the item text: it gives the
  subagent-confinement measurement a shipped home, which is what the three
  script comments now cite, and `cc-platform.md` is the right node for it on the
  merits. The one gap against "the design record is coherent" is out-of-scope
  item A.

## Checks run

```
$ just format-docs
(rc=0; no further fixes — 79 residual rumdl issues across 44 files, none in the
files this review touched)

$ python3 scripts/check-docs-links.py
check-docs-links: 51 decisions, 112 files scanned
  broken-link          0
  unstubbed-decision   0
  stub-without-body    0
  duplicate-decision   0
  duplicate-conclusion 0
  undefined-decision   0
  enumeration-drift    0
  delegation-drift     0
  oversized-file       0
rc=0
```

Line counts after `just format-docs`: `git-hooks-and-entry-points.md` 400/400,
`index-authoring-sync.md` 313/400, `cc-platform.md` 226/400, `decisions.md`
140/400, `design.md` 280/400, `changelog.md` 326/400, the entry file 72/400.

`just precommit` was not run and nothing was staged or committed, per the
dispatch. Three files are modified in the working tree:
`docs/references/git-hooks-and-entry-points.md`,
`docs/references/index-authoring-sync.md` and
`docs/changelog/2026-09-11-the-commit-path-composes-before-it-commits.md`.
