# Tier stores — decisions D42, D43

How each tier's own git store is committed and pinned. The commit and merge
paths reach this node from outside the tiered-memory subsystem, so it reads
standalone; the subsystem's entry point is [tiered-memory.md](tiered-memory.md).
How two writers' concurrent changes to a tier are merged is D44, in
[tier-conflicts.md](tier-conflicts.md).

- Stores — **D42** tier commit/push lockstep is driver-side · **D43** a tier's
  gitlink records what root last composed against, and advancing a tier is a
  take. Both assume the detached-at-`live` branch model, which is D41, in
  [branch-model.md](branch-model.md). The order a take visits the stores in and
  the compose that records them are D77 and D78, in
  [take-and-compose.md](take-and-compose.md); how a take repairs an arrival the
  root index cannot adopt is D52, in
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

**D43 — A tier's gitlink records what root last composed against; advancing a
tier is a take**

Memory's tree records a gitlink for each tier: the commit root's tier block was
last composed against. `SessionStart` moves no tier (D59). It clones a tier that
is not checked out, at the recorded commit, fetches the others read-only and
reports; every other tier stays on the commit and the branch it is on, whatever
its relation to the gitlink. A tier off the gitlink is the commit's pin guard to
refuse (D50); one ahead of it is left where it stands because the take needs it
there to compose its lines up three-way, and the refusal names that take (D78).
Taking an upstream commit is a take, through `/gitlore:merge` or
`/gitlore:push`.

Root's tier block and the carrier it projects are two projections of the same
facts. Root to carrier places lines (D36); carrier to root merges them
three-way, so a carrier line neither side of root held is adopted rather than
lost, and composition refuses nothing for a tier that merely moved.

**Taking is three cases, not one.** Both commands classify each store by
ancestry against the fetched `origin/live`. A remote already contained in `HEAD`
is nothing to take — local commits awaiting publication are the push's business,
and reporting them as waiting would send the user into a merge with nothing to
merge. A `HEAD` that is an ancestor of the remote is taken by **fast-forward**:
the local `live` advances and the working tree follows. No sub-agent — nothing
is in dispute, and spending a synthesis on a fast-forward would make taking
upstream facts expensive enough to skip. Only a genuine divergence prepares a
merge and yields. A tier with uncommitted changes and something to take is
refused before anything moves, because the working tree may hold this session's
unapproved facts; the order and what the run records at its end are in
[take-and-compose.md](take-and-compose.md).

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

**The other direction is a take, and it moves no ref.** A tier's `live` ahead of
its `HEAD` holds commits the take's ancestry test cannot see, since it reads
`HEAD`. Neither ref may be moved onto the other — rewinding `live` discards
approved commits, and moving `HEAD` alone takes the tier off the commit the
store records. `gitlore_adopt_advanced_live` checks the tier out at `live`, the
move a remote arrival gets sourced from the local ref, in every take right after
the take's fetch. A take skips it when the fetched `origin/live` already
contains `live`: the remote fast-forward then takes origin's commits, among them
a repair of the same arrival that another consumer already published, which
adopting the stale copy would repair a second time (D52). No remote, a failed
fetch and a remote with no `live` all adopt, since nothing else reaches those
commits. A dirty tier is refused rather than checked out over.

The memory root is excluded. It has no pin above it — the parent's gitlink is
allowed to lag (D46) — so there a `live` ahead of `HEAD` is answered by checking
`HEAD` out at `live`, the move `/gitlore:merge` makes for the root (D59). A
`HEAD` and `live` that have each moved since they last agreed are reported and
left untouched at every level, because which one was intended is not recoverable
from the refs.

**A prepared merge is detected before anything else touches a tier.** A tier
mid-merge is reported by `SessionStart` with its notice alone, and its working
tree is left as it is: a position read would describe the preparation, which
moved `HEAD` onto its authority, and hint a second remedy.

**A tier merge lands in the tier and records nothing in root.** Its continuation
commits the merge, clears the merge state and advances `live`, publishing only a
merge a refused push prepared and never one `/gitlore:merge` prepared. The
carrier check that keeps a defective merged carrier from landing (D52) stays, on
the carrier alone. The root write and the bookkeeping commit belong to the end
of the take or push run that follows (D77), which finds the tier ahead of its
gitlink; a refusal there is the root's, and the tier stays where the take put
it.
