# Take order and compose — decisions D77, D78

How a take moves every store and then writes root's index once: the order the
stores are visited in, the three-way compose that carries a tier's lines up into
root, and what happens when that compose cannot settle a line. A node of the
tiered-memory subsystem (FR15), whose entry point is
[tiered-memory.md](tiered-memory.md). The tier's own commit and pin are in
[tier-stores.md](tier-stores.md); the repair of an arriving carrier is in
[tier-arrival-repair.md](tier-arrival-repair.md); the divergence path a take
yields to is in [merge-and-resolve.md](merge-and-resolve.md).

- Take and compose — **D77** a take visits every tier first and root last, and
  writes root's index once, in one bookkeeping commit · **D78** a tier's lines
  compose up into root three-way, against the carrier at the gitlink memory's
  index records, and a tier ahead of that gitlink is no fault · in the memory
  merge's continuation a line both sides changed takes the tier's

---

## Mechanism

### The run

`gitlore-merge` (`gitlore_merge_stores`) and the take inside `gitlore-push` do
the same five things, in this order.

1. **Guard every store.** A half-finished merge in any store is answered first,
   then a dirty tier that has something to take is refused, naming it, before
   anything moves. A dirty tier with nothing to take blocks nothing.
2. **Take each mounted tier** (`gitlore_take_tier`): reconcile its `HEAD`
   against its local `live`, take its remote (fast-forward, or a prepared merge
   marked not-to-publish when the two diverged), then check the arrived carrier
   alone and repair it when it fails (D52). Inside a push a tier is taken only
   when it holds arrivals, and its merge is published on landing (D75). A tier
   that yields or refuses stops the run.
3. **Reconcile and take root.** A root fast-forward onto a commit recording a
   tier gitlink that no repository holds is refused; a diverged root prepares
   its merge, which records each tier's `HEAD` itself (below).
4. **Compose and record once** (`gitlore_compose_moved_tiers`). Every mounted
   tier whose `HEAD` strictly descends the gitlink memory's *index* records is
   composed up into root's `MEMORY.md` in one write, the file and the moved
   gitlinks are staged, and one canned commit
   `Update MEMORY.md for <tiers> tier merge.` records them, its body listing the
   subjects each tier's range brought in. Whatever moved a tier counts — this
   run's take, an earlier continuation that landed a tier merge, another
   checkout, a killed run — because a tier off its pin is all the state there
   is. A run that moved nothing writes nothing.
5. **Advance `live`** to the bookkeeping commit with the ff-checked `push .`.

A push composes only after root has taken its remote when merely behind, so the
bookkeeping commit lands on top; a diverged root composes nothing there, because
the refused push that follows prepares the merge, and the merge records the
tiers.

Three outcomes of step 4 other than the commit:

- A root store holding other uncommitted work gets the moves *staged*, not
  committed, for the next approved memory commit: a canned commit would sweep
  that work up. Root's `MEMORY.md` and the tier paths are outside that question,
  since the compose rewrites the file whatever it held (D31) and a take is
  moving the tiers.
- A refusal by the compose records nothing and moves nothing back. Every tier
  stays where its take put it and the next take retries the write.
- A compose that leaves a diff3 chunk writes root with the markers, stages the
  gitlinks of the tiers it merged, commits nothing, and names the file and each
  marker line. The remedy is to resolve each chunk to the line root should carry
  and commit memory. `gitlore_compose_check_index` refuses a file holding a
  marker, so the pending check, the pass and the commit refuse root until the
  markers are gone.

### The prepare records the tier

A root merge meets each gitlink after its tier already moved. A gitlink only
upstream moved git takes silently; one both sides moved conflicts. The answer is
the tier's current `HEAD` either way, so `gitlore_prepare_merge` settles it
without the merger. Ahead of the checkout, for every mounted tier and both
sides' gitlinks, `gitlore_check_tier_gitlinks` requires that the tier holds the
commit (after one fetch of it from the tier's remote) and that the tier's `HEAD`
descends it; a tier merge commit and a fast-forward both do. A failure stops the
prepare before anything moves: a commit no repository holds is the integrity
error of [unresolvable-pin.md](unresolvable-pin.md), and a `HEAD` that does not
descend names `/gitlore:merge`, which takes the tier before memory. After git's
line-wise merge, `gitlore_stage_tier_heads` stages each listed tier's `HEAD`, so
no unmerged gitlink entry reaches the state file, which lists no tier, and the
continuation's merge commit carries the gitlinks. The check lives in the prepare
rather than in the take, so a root merge `/gitlore:resolve` prepares without
visiting a tier gets it too.

### Where the compose runs

`gitlore_compose_up` merges the tiers it is given into root and writes root
once; it writes no carrier, so a merge in one store never propagates into
another the user did not review. It runs at four places, all with the same
three-way:

- the end of a take, for the tiers ahead of the gitlinks the index records;
- the memory merge's continuation, before its commit, for the tiers ahead of the
  gitlinks `OURS` records (`HEAD:` rather than the index, because `HEAD` still
  records `OURS` there and the staged tier heads would read as on their pins
  once the merge commit lands, leaving a carrier line neither root side held
  adopted by nothing). A line both sides changed takes the tier's there, so no
  chunk is written;
- the pass `gitlore-compose` and `PostToolBatch`'s pass
  (`gitlore_compose_pass`), for every active tier off its pin, so a tier another
  checkout or a killed take moved composes like an arrival; a chunk ends the
  pass with root written and the tiers staged, since projecting a block holding
  three versions of one line down would push whichever the projection picked
  into the carrier;
- the commit path's pending check, in its read-only form.

A tier merge's continuation lands the merge and composes nothing: the carrier is
checked on its own (D52), and the compose runs at the end of the `gitlore-merge`
or push run that follows.

### The three-way

For each tier, `gitlore_compose_merge_tiers` runs `gitlore_index_merge` over

- **base** — the carrier at the gitlink memory's index records, prefixed as root
  carries it;
- **ours** — root's block for the tier;
- **theirs** — the tier's carrier at its `HEAD`.

Bullets merge entry-wise by path (D44), with a diff3 chunk only for a path both
sides moved apart, under git's labels: `HEAD`, the base commit and the tier's
`HEAD`. A line only the tier changed is adopted, a line only root changed
stands. A tier on its pin merges to root's own lines, since base equals theirs.
A tier root holds no line for is left out, the mount case. A base commit the
tier does not hold composes nothing and is reported, because an empty base would
read every line root dropped as one the tier added.

## Decisions — D77, D78

**D77 — A take visits every tier first and root last, and writes root once**

My human partner's call. The tiers move before root does, so the root take meets
each gitlink after its tier already moved: a pin only the other side moved is a
tier fast-forward followed by a root merge whose gitlink git takes silently, and
a tier with its own commit lands its tier merge first, after which the root
merge records the tier's `HEAD` and the end compose carries both facts' lines
into root. One `/gitlore:merge` loop takes everything. The reconcile of a
store's `HEAD` against its local `live` follows the same order, since it
prepares root merges through the same function: tiers are reconciled and taken
before root's reconcile.

Root-first existed so that a per-tier bookkeeping commit did not meet upstream
root's equivalent commit as a divergence and spend a synthesis on two sides that
recorded the same fast-forward. With one bookkeeping commit at the end of the
run there is no per-tier commit, and that premise is gone. Publishing keeps
tiers before memory for the opposite reason, that a pointer must never go out
ahead of what it points at (D42).

D52's repair still runs per tier, before root moves: the arrived carrier is
checked alone with `gitlore_compose_check_index`, and the repair's retry
rechecks the carrier, not a compose. Only the root write and the bookkeeping
commit move to the end, so a killed take needs no marker, and no walk-back or
staged pair exists.

**D78 — Tier lines compose up three-way against the index's gitlink, and a tier
ahead of its pin is no fault**

A tier `HEAD` that strictly descends its pin is not a fault. What is wrong, when
anything is, is root's lines for the tier disagreeing with the tier's index, and
the three-way answers it with neither side winning by fiat. The gitlink gives
root's note of what it has seen: a tier fast-forwarded, merged or committed in
since is ahead of it, and the carrier at that gitlink is exactly what root's
block was last composed against.

The base is read from the *index*, not `HEAD`, because staging a gitlink is how
root records that it has seen the tier's version. A chunk resolved to either
side or to neither then stands, where a base read from `HEAD` would rebuild the
same chunk at every pass and commit. That is also why a compose-up that leaves a
chunk stages the merged tiers.

That rule is the scope of the take's compose and of every pass outside a memory
merge. The memory merge's continuation is the standing exception: it reads the
gitlinks `OURS` records from `HEAD:` (above), because the index there already
holds the staged tier heads. That base cannot record what root has seen until
the merge commits, so a line both the merged root and the tier changed apart
takes the tier's line there, reported on stderr as
`tier '<tier>' replaced root's line for <path>: <root's line>`, rather than a
chunk that would recur on every rerun.

`/gitlore:merge` brings in changes from `live` and gains no adoption step, and
there is no `gitlore-compose --up`. The commit path commits through a tier ahead
of its pin and its `add -A` records the gitlink (D50). The orphan report also
runs at the commit and at `SessionStart`, since a line the tier added changes
nothing in a pass and the pending check does not see it.

**The trade-off of staging on a chunk.** A user who discards root's markers with
`git checkout -- MEMORY.md` and lets the pass run gets root's old text projected
over the tier's committed reword in the carrier: the gitlink is staged, so the
tier reads as seen, and the down projection writes root's block into the
carrier. That is the overwrite D36 names, and the pass reports it only as
`composed`. Resolving the chunk in the file, which the report asks for, is the
path that loses nothing.

A line a tier ahead of its pin added cannot be deleted from root, because the
pass re-adopts it, and a reword in root of an adopted line comes back as a chunk
with an empty base section. Staging the merged tiers after every compose-up, not
only one leaving markers, would record what root has seen; whether to is an open
question.

## Rejected alternatives

**Visiting root first, with a per-tier bookkeeping commit.** The root-first
order's only premise was avoiding a divergence between the per-tier commit and
upstream's equivalent one; one end-of-run commit removes the premise (D77).

**Keeping the per-tier root write, staged pair and walk-back.** Each tier take
wrote root and committed the pair, and a refusal walked the tier back to its
pin. Writing root once at the end leaves nothing to walk back and no kill window
between the write and the stage (D77).

**A marker recording a killed take.** A tier a killed run moved with root
unwritten is a tier off its pin whose carrier holds lines root lacks, and the
three-way adopts them at the next pass or take, so the state is its own record
(D77).

**An overwrite compose-up.** The earlier up projection replaced root's block for
a tier with the carrier's, so a line root changed was lost, and a tier ahead of
its pin had to be put back for it to be safe. The three-way keeps both sides'
changes and chunks only a line both moved apart (D78).

**A base read from `HEAD`.** It rebuilds the same chunk at every pass and every
commit, because nothing records that root has seen the tier's version (D78).
Rejected for the take and the passes; the memory merge's continuation keeps it
as D78's stated exception, with the tier-wins rule above.

**Recording in the merge state which tier commits the continuation has offered
root as a chunk.** It would make the continuation's base depend on state and add
a second base rule beside the gitlink, where a tier-wins line gives one
consistent answer: a merge always takes in the index update from the tiers
(D78).

**Composing in the prepare.** `gitlore_compose_check` refuses a `MEMORY.md`
holding git's markers (rules 8, 1 and 4), and composing over the entry-wise
merge would nest a tier chunk inside a root chunk (D78).

**An adoption step in `/gitlore:merge`, or `gitlore-compose --up`.** The
three-way compose answers any disagreement between root and a tier, so a step
that decides which side wins adds surface and loses the other side's change
(D78).
