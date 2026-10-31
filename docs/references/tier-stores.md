# Tier stores — decisions D42, D43

How each tier's own git store is committed and pinned. The commit and merge
paths reach this node from outside the tiered-memory subsystem, so it reads
standalone; the subsystem's entry point is [tiered-memory.md](tiered-memory.md).
How two writers' concurrent changes to a tier are merged is D44, in
[tier-conflicts.md](tier-conflicts.md).

- Stores — **D42** tier commit/push lockstep is driver-side · **D43** a tier is
  pinned at its gitlink, and advancing one is a merge. Both assume the
  detached-at-`live` branch model, which is D41, in
  [branch-model.md](branch-model.md). How a take repairs an arrival the root
  index cannot adopt is D52, in
  [tier-arrival-repair.md](tier-arrival-repair.md).

---

**D42 — Tier commit/push lockstep is driver-side, with one approval per
episode**

A tier commit rides the same before-and-alongside staircase the parent already
applies to memory, one level deeper: `gitlore_sync_tiers_to_live` commits every
dirty tier and advances its local `live` *before* memory's own `git add -A`, so
the moved gitlink is part of the memory commit rather than lagging it;
`pre-push` pushes each tier's `live` to its own remote *before* memory's, so the
pointer never goes out ahead of what it points at. Two decisions the shared
driver rests on:

*One approval per memory episode, not per tier.* The episode's summary is shown
and approved once, and carries one section per store it touched; each store's
commit takes its own section verbatim (D70). The user approves a set of
*writes*, not a set of repositories; N prompts for one decision buys no extra
information. What the approval owes the user is **grouping by destination** — a
line bound for a shared tier is more public than one bound for project memory,
and the sections keep a private store's paragraphs out of a shared tier's log.

*No recursing hook in the memory store.* Recursion is driver-side, exactly as
the parent already drives memory: `commit-memory.sh` calls the sync function and
`pre-push` pushes explicitly, rather than relying on a hook one level down. A
hook-side version would re-litigate the full `--local-env-vars` unset and the
`GIT_INDEX_FILE` capture/restore at a level that needs neither. No hook runs in
the memory store or a tier at commit time (D70).

Scope is every **mounted** tier, not only the active ones: the manifest governs
routing and composition, and silently dropping a dormant tier's writes would be
data loss rather than dormancy. Each loop guards `[ -e "$tierpath/.git" ]`
before any `git -C` — into an unchecked-out submodule that escapes to the
enclosing repo, which would have committed *memory* under the tier's name and
pushed memory's `live` to the tier's remote. Tier divergence surfaces at both
points — the pending commit against the tier's local `live` (`head-vs-live`,
found by the reconcile in merge and push) and local `live` against the tier's
own remote (`head-vs-remote`) — is reported by tier name with git's own reason,
and resolves through the same merge path as memory: each yields to
`gitlore_yield_merge`, the state file names the store the merge was prepared in,
and the continuation finds it by walking the stores
([workflows.md](workflows.md)).

**D43 — A tier is pinned at its gitlink; advancing one is a merge**

SessionStart checks each tier out at the commit the memory tree records for it —
`submodule update --init`, on every session and not only when the tier was never
materialized, since a clone made before this model already sits ahead of its
gitlink and has to be put back — and nothing advances it silently. One memory
commit records the root `MEMORY.md` and the tier gitlink together, so root's
tier block and the carrier index it projects are consistent *by construction*; a
tier that fast-forwarded on its own leaves root describing one commit and the
carrier holding another, and nothing downstream repairs that — composition
places lines, it does not merge them. So composition refuses instead: the down
projection compares each active tier's `HEAD` against the gitlink the memory
store's index records and writes nothing when they differ, because projecting
root's older block onto a carrier nothing adopted up overwrites approved
upstream text and reports success (D31). Taking an upstream commit is therefore
a merge, through `/gitlore:merge` or `/gitlore:push`.

**Taking is three cases, not one.** Both commands classify each store by
ancestry against the fetched `origin/live`. A remote already contained in `HEAD`
is nothing to take — local commits awaiting publication are the push's business,
and reporting them as waiting would send the user into a merge with nothing to
merge. A `HEAD` that is an ancestor of the remote is taken by
**fast-forward plus adoption**: the local `live` advances, the working tree
follows, and the arrived carrier is projected up into root's block for that
tier. No sub-agent — nothing is in dispute, and spending a synthesis on a
fast-forward would make taking upstream facts expensive enough to skip. Only a
genuine divergence prepares a merge and yields. A store with uncommitted changes
is refused rather than checked out over: the working tree may hold this
session's unapproved facts.

**Nothing to take is not nothing to do.** That first case is decided from
`HEAD`, while the ref a push sends is `live`, and a store rests detached *at*
`live` — so a `live` strictly behind a `HEAD` that contains it is a ref that
failed to keep up rather than a state anything chose, and the take advances it
with a local ff-checked `push . HEAD:live` rather than leaving it there. The
publish preflight repairs that direction the same way and in place of the drift
report it would otherwise make
([memory-entry-points.md](memory-entry-points.md)). The move itself publishes
nothing: every commit in `HEAD` reached it through a gate. The producer is a
merge preparation that checked `HEAD` out at `origin/live` and could not
continue, which leaves the remote contained in `HEAD` and `live` where it was —
the store then calls itself finished on every later take while every push is
refused as a non-fast-forward. That direction is the one *repaired*.

**The other direction is a take, and a checkout is what breaks it.** A tier's
`live` ahead of a `HEAD` sitting at the pin holds commits the memory store never
recorded — a tier commit advances both refs together, so the two part only when
the memory side loses the moved gitlink afterwards (a merge preparation checks
the memory store out and rewrites its index), and the next SessionStart pins
`HEAD` back while `live` keeps what was approved. Nothing reports it: `live` is
invisible to the take's ancestry test and to SessionStart's, both of which read
`HEAD`. Neither ref may be moved onto the other — rewinding `live` discards
approved commits, and moving `HEAD` alone takes the tier off the commit the
store records, which is precisely the state the down projection refuses. So the
publish gate's bare "put `HEAD` back on `live`" remedy is the one that breaks
the store, and a tier is sent to the take instead. `gitlore_adopt_advanced_live`
runs the same fast-forward-plus-adoption a remote arrival gets, sourced from the
local ref and moving no ref at all, from the publish preflight and in every
take, right after the take's fetch. A take skips it when the fetched
`origin/live` already contains `live`: the remote fast-forward then takes
origin's commits, among them a repair of the same arrival that another consumer
already published, which adopting the stale copy would repair a second time
(D52). No remote, a failed fetch and a remote with no `live` all adopt, since
nothing else reaches those commits. `gitlore_adopt_tier_into_root` is the tail
the two share. The preflight runs the *whole* take pass rather than adopting the
one tier, for the reason the behind-tier branch gives: it goes root-first, and a
tier's bookkeeping commit would otherwise meet an equally-behind root's upstream
one as a divergence.

The memory root is excluded from that adoption. It has no pin above it — the
parent's gitlink is allowed to lag (D46) — so there a `live` ahead of `HEAD` is
answered by checking `HEAD` out at `live`, the move `/gitlore:merge` makes for
the root (D59) and the one the gate names for the root and only the root. A
`HEAD` and `live` that have each moved since they last agreed are reported and
left untouched at every level, because which one was intended is not recoverable
from the refs.

The tier fetch stays, **read-only**: `fetch origin live` with no refspec moves
no local branch, and its only job is to let SessionStart *name* a tier whose
remote is ahead or has diverged, by comparing `HEAD` and `FETCH_HEAD` for
ancestry. Ancestry rather than a refusal message, because a fetch that attempts
no ref update is refused for nothing — and ancestry is what distinguishes an
upstream arrival from local commits merely awaiting their lockstep push, which
must not be reported as waiting. A prepared merge is detected *before* anything
checks out: `git checkout`, which `submodule update` runs, unlinks `MERGE_HEAD`
and `MERGE_MSG` silently and on success, so a tier mid-merge is skipped entirely
and said so on both channels. A tier that arrived attached to a branch is
detached in place (no ref argument, so the commit does not move) — the branch
model has no working branch, and a commit made on one would advance a ref the
lockstep never reads.

The recomposition that follows is **committed by the take itself** (D49, in
[merge-and-resolve.md](merge-and-resolve.md)): the moved gitlink and the
recomposed root index land in a canned bookkeeping commit
(`Update MEMORY.md for <tier> tier merge.`) that advances memory's local `live`,
so an explicit take leaves the store clean. The parent-level gitlink still
floats to the next parent commit, as every memory advance leaves it (a commit
through `gitlore-commit` and the canned mount commit `gitlore-add-tier` makes
are the advances that stage it, D71). One path degrades: a root store that held
unapproved work *before* the take gets no canned commit — the pair includes
`MEMORY.md`, whose recompose folds in whatever unapproved index edits the
episode already held — and falls back to the staged-pair discipline below.

**A take whose up projection fails records nothing and walks the tier back.**
Staging the gitlink would put the tier on its pin while root still holds the
older block, and the next compose would write that text over the carrier with
nothing left to refuse (D50). Leaving the tier ahead of an unstaged pin instead
has the pin guard refuse every commit until `SessionStart` walks it back, while
a take finds nothing to take. So `gitlore_adopt_tier_into_root` checks the tier
out at its pre-take commit and fails the take. What the take brought in stays in
the tier's local `live`, the shape `gitlore_adopt_advanced_live` adopts, so the
next take retries the whole adoption once the refusal is fixed. The checkout
loses nothing: a take refuses a dirty tier, and the up projection writes no
carrier. A refusal in which a problem names the arriving carrier is repaired
before it walks anything back (D52). The tier walks back only when no problem
names the carrier, when the repair cannot be built or cannot fix the carrier,
when `live` cannot take it or the worktree cannot follow, or when the retry
still refuses on what this repo holds. The walk-back names what the tier's local
`live` keeps: the repair, once it is there — after a refused retry, or a
checkout that could not follow the advance — and otherwise what arrived.

**A take killed between the root write and the staged pair is an accepted
residual.** `gitlore_compose_up` writes root's `MEMORY.md` as an ordinary
working-tree write, and `gitlore_adopt_stage_pair_and_commit` stages the pair
afterwards, so a kill between the two leaves root describing the arrival over a
gitlink that never moved. A take retried at once finds nothing to take. The next
`SessionStart` pins the tier back, the pin guard then has nothing to refuse, and
the down projection writes root's line into the carrier for a file the tier no
longer holds; the dangling report names root's line and nothing names the
carrier. A take after that refuses the dirty tier. What recovers it is the
commit path followed by the reconcile: the carrier line is committed on the pin,
its `HEAD:live` advance is refused as a non-fast-forward because `live` still
holds the arrival and is reported as a fork, and the `head-vs-live` merge that
the next `/gitlore:merge` or `/gitlore:push` prepares and `/gitlore:resolve`
lands joins the line to its file and stages the pair. Nothing is lost at any
step, and the cost is one merger dispatch and a redundant commit in the tier's
history, for a failure that takes a kill inside one function.
`tests/killed_take_repro.bats` pins the whole sequence.

**A tier merge the root index cannot adopt still lands, and the root records
none of it.** A merged carrier that fails the check never gets here: that merge
commits nothing and stays prepared for a new synthesis (D52). What reaches this
path is a refusal elsewhere, in root, the manifest or another tier. The
continuation commits the merge in the tier, clears the merge state and advances
`live` — publishing only a merge a refused push prepared, never one
`/gitlore:merge` prepared — then skips the gitlink staging and the bookkeeping
commit for the reason above. Once nothing is left to yield on, it checks the
tier out at the pin the memory store's index holds, the merge kept in `live`. It
exits 0 when its pushes went through, because the merge landed, and exits 1
after resting the tier when a push is refused for any reason but divergence. It
prints the remedy — fix the store and run `/gitlore:merge` — and the next
`/gitlore:resolve` run refuses the tier's `live` ahead of `HEAD` with the same
one.

Three cases leave the tier off its pin. A yield leaves it alone, because the
merge it prepares sits at `HEAD` and that merge's own continuation retries the
adoption. A pin the merge does not contain is not checked out either, since that
would put the tier on history the merge never built on; the tier stays on the
merge, and the pin guard at the next memory commit names the remedy. And the
tier rests on its pin only when its local `live` holds the merge. A refused
local `HEAD:live` push leaves `live` short of it, and checking the pin out would
leave the merge reachable only through the reflog, so the tier stays on the
merge. The continuation prints two commands that finish the rest by hand, to be
followed by fixing the problems it listed and running `/gitlore:merge`:

```text
git -C "<abs>" push . HEAD:live
git -C "<abs>" merge-base --is-ancestor HEAD live && git -C "<abs>" checkout --detach <pin>
```

The second re-asks the guard's own question, so run after a push refused again
it leaves the tier where it is.

**On the degraded path, the moved gitlink is staged.** `submodule update` checks
a tier out at the sha the superproject's **index** holds, not the one its HEAD
records, so the pin and a floating gitlink are only compatible while the move is
in the index. Every advancing path therefore stages the pair — `MEMORY.md` and
the tier — before its bookkeeping commit, and keeps the staged pair when that
commit is refused: the fast-forward-plus-adoption branch of
`gitlore_merge_stores`, and the merge continuation when the root adopted its
tier, which stages *after* its merge commit because that commit does not exist
before it. The **mount** is a third such path and stages the gitlink alone:
`submodule add` records the remote's default branch and `/gitlore:add-tier` then
detaches the tier at `live`, so the gitlink moves while the root index it feeds
is written by the compose that follows and floats as ordinary dirt. Left in the
working tree alone, the move survives exactly until the next `SessionStart`,
which walks the tier back to the pre-merge commit while the recomposed root
index — an ordinary file write, not a gitlink — survives to describe facts the
carrier no longer holds. Nothing reports it: the command that landed the merge
exited 0, and the session that reverted it calls the tier clean. Staging is what
makes the pin idempotent instead of destructive.

## Rejected alternatives

**A down projection that skips a root line whose file the tier does not hold.**
Would keep the carrier clean after a killed take, so the next take re-adopts
unaided. But it changes the down pass's contract for every tier to cover one
kill window, and the divergence path already recovers the state with nothing
lost (D43).

**Writing root and staging the pair atomically.** Closes the killed-take window
itself, at the cost of `gitlore_compose_write`'s contract with every other
caller, which would keep the same window unless each took the same change (D43).
