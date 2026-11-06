# Tier arrival repair — decision D52

What a take does with an arriving tier index the root cannot adopt, and what a
merge continuation does with a merged index that fails the same check. A node of
the tiered-memory subsystem (FR15), whose entry point is
[tiered-memory.md](tiered-memory.md). The take and the pin this builds on are in
[tier-stores.md](tier-stores.md), the order of a take and its end compose in
[take-and-compose.md](take-and-compose.md); the check's rules are in
[index-composition.md](index-composition.md).

- Defective indexes — **D52** a take repairs an arrival whose index structure
  the root cannot adopt, with a plain commit on the arrival that restructures
  and never rewords, and a merge whose merged index fails the check does not
  land

---

**D52 — A take repairs an arrival the root index cannot adopt; a merged index
that fails the check does not land**

A carrier that arrives with a duplicate pointer, a non-bullet line inside the
pointer block or a welded line fails `gitlore_compose_check`. Left unrepaired,
it wedges the tier: the take refuses on the arrival held in `live`, every later
take refuses the same way, and every push retakes and fails. Nothing local
reaches it: the worktree carrier the refusal names is clean, a take refuses a
dirty tier, the pin guard refuses a tier checked out at `live`, and a hand
commit on `live` bypasses the approval gate. D50's abort
([git-hooks.md](git-hooks.md)) stops a gitlore commit publishing such a defect
in an index file it changes; a hand push or an older gitlore still can. So the
take repairs what arrives, and what this repo authors — a commit, a merge
synthesis — is refused and re-authored.

**The repair is a plain commit on top of the arrival.** When a problem the
refusal prints names the arriving carrier — by the exact `<file>: ` prefix,
against the memory path the check was given (`gitlore_compose_problems_in`) —
`gitlore_adopt_repair_arrival` repairs a scratch copy of the carrier outside the
repository, in a `mktemp -d` directory under `$TMPDIR` or, where that is unset,
`/tmp`, and rechecks it. It builds the commit from a temporary index with
`commit-tree`, the arrival as its only parent, subject
`Repair the MEMORY.md structure <tier> received` and one body line per edit. It
advances the tier's local `live` with an ff-checked `push .`, checks the tier
out at `live`, and rechecks the carrier. History stays linear (D6), nothing
yields, and no merge machinery runs, so the entry-wise index pass never touches
a line the rules do not name. The commit is unprompted under D49: it adds no
text to lines that already passed an approval gate. Once `live` holds it, the
take prints `gitlore: repaired <t>'s arrival: <edit>` for each edit, naming each
dropped line verbatim.

**The worktree never holds the repair uncommitted**, because a carrier written
there first would strand a killed take: `submodule update` cannot check the pin
out over a modified `MEMORY.md`, the pin guard then refuses every commit, and
the take refuses the dirty tier. As built, a take killed at any point leaves the
tier clean — on the arrival or the repair — with `live` on the arrival or the
repair; the next take repairs again or finds the repair already there. The
repair is deterministic, so losing one costs nothing, and `commit-tree` runs no
hook, so no sentinel is needed.

**A failed repair leaves the tier where the take put it.** Each step that can
fail — the scratch directory, the arrival and pin reads, the rewrite, the commit
build, the `live` advance, the checkout that follows it — prints its own failure
line, then the full refusal under
`gitlore: the root index could not take tier '<t>''s lines:`, and the line
`nothing was recorded, and tier '<t>' stays where the take put it.`; the take
exits 1. A refused advance leaves the repair commit unreachable, with the tier
and `live` on the arrival. These failures are transient, so the remedy is
`Run /gitlore:merge again.`: the next take repairs from scratch.

**The repair restructures and never rewords.** `gitlore_repair_index` applies
three rules, in this order:

1. **Welds.** A welded line is split before the second link's `- [`, exactly the
   shape `gitlore_welded_path` reports, until none remain — but only when the
   second path names an existing file inside the tier, which a path with a
   leading `/` or a `..` component never does. Welds go first because a weld can
   hide a duplicate.
2. **Stray lines.** Non-blank non-bullet lines inside the pointer block move
   verbatim, keeping their order, to just after the last bullet.
3. **Duplicates.** Of the lines sharing a path, the first one the pin's carrier
   lacks survives at its own position, or the first of them when the pin's
   carrier lacks none; the rest are dropped. A pin with no carrier reads as
   empty.

Every other line keeps its bytes and relative order. A wrong pick among
duplicates is named in the report and corrected upstream as an ordinary edit. A
rule added to `gitlore_compose_check_index` gains its repair rule in the same
change, or the take refuses for that rule. This is the line D50 records: a
consumer leaves the wording of what upstream sent alone, and a structural defect
the root cannot adopt is the take's to repair.

**The carrier's lines are the repair's; everything else is this repo's.** The
repair runs per tier, on the carrier alone, ahead of root's write. A refusal at
the end compose on root, the manifest or another tier leaves the tier on the
repair, which is committed in its local `live` and checked out, records nothing,
and closes `Fix the store, then run /gitlore:merge again.` — the store is what
needs fixing here, unlike the transient arms above. The next take or push finds
the tier ahead of its pin and composes it with no second repair. With no problem
naming the carrier nothing is repaired. When the recheck still fails — a weld
whose second path names no file in the tier — nothing is committed, the report
attributes the carrier's problems to `live:MEMORY.md` rather than the clean
worktree carrier, and it closes
`Once the index is fixed where it was published, run /gitlore:merge again.` That
tier stays wedged, every take refusing at the repair and every push failing,
until upstream edits the line. Tiers are taken one at a time and the first
failure stops the pass, so several defective arrivals are repaired in turn.

**A repair publishes the way its take does.** A take inside a push publishes it
in that push, ahead of memory's push recording its gitlink (D42). Two places in
the tier loop run the take — `live` ahead of `HEAD`, and a tier push refused as
`behind`, which pushes that tier again when the take left `live` ahead of
`origin/live`. Either can repair a tier other than the one being pushed. After
the tier loop, before memory's push, one pass pushes every tier whose `live` is
not an ancestor of its `origin/live`, so a repair to a tier whose own iteration
already finished goes out too. That take prints
`gitlore: tier '<t>' — the repair is committed in its local 'live', and this push publishes it.`;
under `/gitlore:merge` the line ends `; /gitlore:push publishes it.` A repair
whose record waits on local problems still reaches the tier's remote, and not
memory's (D75). A consumer whose `live` holds the arrival fetches before it
adopts, so it fast-forwards onto a repair another consumer already published
instead of making its own ([tier-stores.md](tier-stores.md)); two that repair
before either publishes meet as an ordinary divergence at the later push.
`pre-push` publishes without the check, and the repair is what covers that
downstream.

**A merge continuation refuses to commit a merged index that fails the check.**
Before staging, `compose_merged_indexes` exits 1 on any problem in the merged
index — the tier's carrier for a tier merge, a duplicate, interleaved or welded
line in root's `MEMORY.md` for a memory-root merge — printing
`gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:`
and only those problems. The merge state, `MERGE_HEAD`, the pending ref and the
merger's staging stay, and the resolve skill answers with `rejected:` and the
problem lines. Those lines are recorded in the merge state, so every later gate
re-emits them with the directive and a session that never saw the refusal briefs
its sub-agent on them ([merge-state-recovery.md](merge-state-recovery.md)).
Every such problem is in the named file's own text, inside the merger's store,
so one edit clears it. A problem outside the merged index lets the merge land: a
tier merge lands in the tier and the end of the run records it (D77, in
[take-and-compose.md](take-and-compose.md)), and a memory-root merge commits
uncomposed. A tier merge's gate reads the carrier alone and composes nothing; a
memory-root merge's compose-up takes the tier's line where both sides changed
one, and leaves no chunk. A defect arriving across a divergence therefore
reaches the synthesis, never the repair. A store with no root `MEMORY.md` runs
no index check, so none of the abort, the repair or this gate applies to it —
which the composition hook reports once an episode rather than leaving silent
([index-composition.md](index-composition.md)).

**A merge continuation refuses to commit files that still hold conflict
markers.** Before composing or staging anything, `compose_merged_indexes` scans
the files the merge changed, in the working tree, for `<<<<<<<` or `>>>>>>>` at
column 0 followed by a space or the end of the line. That covers a conflict the
merger never staged, which the continuation's own `git add -A` would otherwise
mark resolved. On a hit it exits 1, printing
`gitlore: these files still hold conflict markers, so the merge was not committed; the merge stays prepared for a new synthesis:`
and each file name. The merge state and `MERGE_HEAD` stay and root's index stays
as it was, and the refusal empties the index problems the merge state recorded.
It runs before the index gate, so it has no verdict on this synthesis: the field
is emptied so that no earlier verdict is carried onto a synthesis nobody
checked, and the next continuation run checks the index and records what it
finds. Empty means unchecked, not clean. The resolve skill answers with
`rejected:` and the file names. A file the merge left unchanged is not read, so
it may document markers; one the merge changed that documents them at column 0
is refused too, and the merger rewords it. The scan runs first so a tier merge
writes nothing into root's `MEMORY.md` for a merge that did not land.

## Rejected alternatives

**A message fix alone.** The refusal named a worktree carrier that is clean, and
naming the arrival instead still leaves every take refusing and every push
failing, with no local remedy for the message to point at (D52).

**A push that tolerates the defect.** Publishing past the refusal leaves the
arrival unadopted in every consumer, the root never taking its lines, and the
defect in place where no take can reach it (D52).

**A `--no-ff` merge of the arrival onto the pin.** A merge used for convenience,
with no two histories to join. It inverted D6's parent order and needed four
patches — the pin guard, the recovery target, the entry-wise pass and marker
completion — where a plain commit needs none (D52).

**An agent-driven repair through the memory-merger.** Every edit the rules allow
is computable, so it is the script's to make (D7), and the agent shape needed a
repair state, its detection and recovery arms, a landed-repair scan and an
exception in the merger's contract (D52).

**A mechanical repair of a merge synthesis.** A synthesis is authored here, by
an agent holding the named file and the judgement a pick among duplicates needs.
Refused, it is re-synthesized with the problem lines in hand; repaired, a
mechanical pick would override the synthesis it exists to produce (D52).

**Repairing only when every problem names the carrier.** An arrival beside a
local problem would stay unrepaired, so fixing the local problem would still
leave the take refusing on the carrier. Repairing first leaves the repair in
`live`, and the local fix alone then lets the next take adopt it (D52).

**A continuation that commits a defective merged index uncomposed.** It lands a
defect this repo authored, and a publishing merge sends it to every consumer,
whose takes then repair it one by one. Refusing costs one edit to the synthesis
(D52).

**A scratch directory in the tier's gitdir.** It keeps the scratch copy inside a
repository, which is exactly what a killed take then leaves behind, and cleaning
it up needs a library-level `trap` that clobbers whatever trap the caller
installed. `${TMPDIR:-/tmp}` puts the copy where nothing in a repo can be
stranded by it (D52).

**A sweep of stale `gitlore-repair.*` directories on the next repair.** It races
a concurrent take: the directories carry no owner, so a sweep cannot tell a
leftover from the scratch copy another take is repairing in right now, and
removing that one loses its work mid-repair. A killed take's leftover is a few
kilobytes under the system temporary directory, which the system reclaims on its
own schedule (D52).
