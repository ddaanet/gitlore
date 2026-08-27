# 2026-08-27 — A merge preparation records its state file before it starts, so no window inside it is invisible (FR13, D7)

Reported from another repo. A `/gitlore:push` run in `edify` hung past a
two-minute tool timeout and was killed, after `gitlore_prepare_merge` had
checked the authority out detached and completed a clean, non-conflicting merge
of the tier's unpublished tip — a real `MERGE_HEAD`, a real staged 3-way blend
of the tier's own `MEMORY.md`, confirmed afterwards against a fresh
`git merge-tree --write-tree` — but before `gitlore_write_merge_state` recorded
any of it. The state file is what every gate discriminates on, so the store held
a genuinely started merge that nothing could see.

The next run's own `checkout --detach` then unlinked that `MERGE_HEAD`
(`remove_branch_state()`, silently, on a checkout with no unmerged entries to
refuse over), and each retry after it repeated the same misdiagnosis. Recovery
took reading gitlore's source to hand-write the missing state file, so the real
continuation could commit and publish the merge rather than a substitute.

The state file now goes down first. `gitlore_yield_merge` writes a marker —
store, flavor, both sides, continuation, everything known before a merge exists
— then prepares the merge, then overwrites the marker with the full state file
and its briefing. Every window inside the preparation leaves a file for the next
gate, and the marker is dropped with the pin when the preparation refuses
outright, so a merge that was never started leaves nothing to classify.

Two shapes reach a later gate, and the existing classifier already sorts them:

- **Interrupted after the merge staged.** `MERGE_HEAD` is present, so this is
  the ordinary continued merge — except the marker carries no briefing, and the
  merger sub-agent reads `changed_files` first. `gitlore_complete_merge_state`
  fills it in from the merge the store holds, which is where the briefing was
  always computed from, and the directive goes out unchanged. It runs at both
  points where a state file reaches that sub-agent, the guard and the
  pointer-restoring repair, so no path can hand over a marker.
- **Interrupted before the merge ran.** No `MERGE_HEAD`, nothing staged, nothing
  landed — the same three questions the checkout-cleared repair asks, with the
  same disposal: HEAD back onto the pending commit before the pin is dropped,
  every artifact deleted, the gate carrying on to prepare the merge again. Only
  the message differs, because no abort happened and saying one did would send
  the reader looking for it.

`changed_files` is the discriminator between a marker and a full state file: the
first field the sub-agent reads, and the one no marker can carry. The base a
completion needs is recomputed from the two recorded sides rather than stored,
which describes the authority the merge was built on unless that ref moved
during the interruption — the trade the path already makes for any merge that
outlives its session, and the continuation's own refused push re-prepares it.

`MERGE_HEAD` with no state file consequently no longer means an interrupted
gitlore run — gitlore records its preparations before it starts them. It means a
merge something else began: a `git merge` run in the store by hand, or by an
agent asked to merge one. It blocks, and it is reported with the store's
`status --short` and `merge --abort` rather than repaired, since nothing there
says what the merge was for and it may hold work in progress.

Four cases in `tests/resolve_recovery.bats`, each watched failing first: the
marker is present when the preparation runs and gone when it fails; an
interruption after the merge staged is completed and continued rather than
flagged; one before the merge ran is discarded and re-prepared by the gate; and
a hand-run merge blocks with the wording for a merge gitlore did not prepare.
The first drives the failure by overriding `gitlore_prepare_merge` and recording
whether the file existed when it was called, so the ordering itself is asserted
rather than its consequence.
