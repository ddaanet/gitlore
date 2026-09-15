# 2026-09-15 — An arrival the root index cannot adopt is repaired (D50, D52)

A tier carrier that arrived with a duplicate pointer, a non-bullet line inside
the pointer block or a welded line failed the take's up projection. The take
walked the tier back with the arrival in its local `live`, so every later take
refused the same way, `gitlore_push_stores` retook whenever `live` was ahead,
and every push failed. The message named a worktree carrier that was clean, and
nothing local could reach the defect: a take refuses a dirty tier, the pin guard
refuses a tier checked out at `live`, and a hand commit on `live` bypasses the
approval gate. Upstream had published it because the commit path treated a
compose refusal as advisory.

The commit path now aborts on a duplicate, interleaved or welded line in root's
`MEMORY.md` or a tier carrier when that file has uncommitted changes — the one
commit that would publish it (D50). The abort lists every changed index file
with a problem, restamps the approval and asks for an edit to the named lines.
The same problem in a file with no uncommitted changes, and the manifest and
leftover-prefix rules, still report and let the commit go ahead. The standalone
`PostToolBatch` commit keeps retrying, and its message to the agent now defers
to a fix the reason names instead of promising no action is needed.

A take now repairs the arrival itself when a problem names the arriving carrier
(D52). It splits a welded line when the second path names an existing file
inside the tier, moves stray lines to just after the last bullet, and drops
duplicate pointers, keeping the first line the pin's carrier lacks. The repair
is a plain commit on top of the arrival, built with `commit-tree` so the
worktree never holds it uncommitted; it advances `live` and the adoption is
retried. The take prints `gitlore: repaired <t>'s arrival: <edit>` for each
edit, then
`gitlore: tier '<t>' — the repair is committed in its local 'live'; /gitlore:push publishes it.`
under `/gitlore:merge`, or `… in its local 'live', and this push publishes it.`
when the take ran inside a push. Both push arms publish the repair before
memory's push records it: the `behind` arm pushes the tier again when its take
left `live` ahead of `origin/live`. A retry refused on root, the manifest or
another tier rests the repair in `live` for the next take to adopt with no
second repair. An arrival the repair cannot fix walks back as before, listing
its problems as `live:MEMORY.md` lines and closing
`Once the index is fixed where it was published, run /gitlore:merge again.` A
take also fetches before it adopts a local `live`, and skips that adoption when
`origin/live` already contains it, so a consumer resting with an arrival takes
another consumer's published repair instead of making its own.

A merge continuation no longer commits a merged index that fails the check. A
tier merge whose carrier has a problem, or a memory-root merge whose root index
has a duplicate, interleaved or welded line, exits 1 with
`gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:`
and those problems, keeping the merge state and `MERGE_HEAD`. The
`gitlore:memory-merger` agent quotes the lines and stops, and the resolve skill
rejects with them so the merge is re-synthesized. An unapproved parent commit
over such a kept tier merge re-emits the continuation directive instead of
asking for a summary. Problems outside the merged index still let the merge
land.

The continuation's push refusals now return a status instead of exiting, so a
push refused for any reason but divergence rests an unadopted tier and then
exits 1. The rest checks the tier out at its pin only when the tier's local
`live` holds the merge. After a refused local `HEAD:live` push it leaves the
tier on the merge and prints

```text
gitlore: tier '<t>' stays on the merge commit because its local 'live' does not hold it. Run:
gitlore:   git -C "<abs>" push . HEAD:live
gitlore:   git -C "<abs>" merge-base --is-ancestor HEAD live && git -C "<abs>" checkout --detach <pin>
gitlore: then fix the problems listed above and run /gitlore:merge.
```

and the resolve skill relays it as still to run. A merge commit refused by a
hook leaves no message file behind. `/gitlore:resolve` now gates every tier
before memory: memory gated first had published its pointer to a tier merge and
then met that tier's refused push, leaving memory's remote recording a commit
the tier's remote lacked. When memory and a tier both need a merge, the tier's
directive comes first.

A message fix alone and a push that tolerates the defect were rejected, since
neither leaves any consumer able to adopt the arrival. So were a `--no-ff` merge
of the arrival onto the pin, which joins no two histories and needed four
patches, and an agent-driven repair through the memory-merger, when every edit
is computable. A synthesis is refused rather than repaired, because this repo
authors it; the repair is for what arrives.
