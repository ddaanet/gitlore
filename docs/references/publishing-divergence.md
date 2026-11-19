# Publishing a divergence — decisions D75, D76, D86

Why a divergence is published rather than carried, what the position report
hints because of it, and what publishes: a push publishes each store as soon as
it is ready (D75), the position line names `/gitlore:push` for any divergence,
`/gitlore:merge` only for a take that is a fast-forward (D76), and only
`/gitlore:push` publishes (D86). The three share one argument. The divergence
path they sit on, `gitlore_reconcile_one` and the prepared merge, is in
[merge-and-resolve.md](merge-and-resolve.md); what `live` is and which side of a
merge is authoritative are in [branch-model.md](branch-model.md). The one-line
report of every store's position (D84) is argued in
[session-decisions.md](session-decisions.md); the table of what a module
reports, which it reads, is in [session.md](session.md).

- Publishing — **D75** a push publishes each store as soon as it is ready; a
  merge landed for a push is local and the rerun push publishes it · **D76** a
  divergence names `/gitlore:push`; `/gitlore:merge` is named only for a
  fast-forward take · **D86** only `/gitlore:push` publishes; `/gitlore:resolve`
  lands locally

---

## The argument

**Pushing your divergence is what puts you back on `live`.** A store whose
history has diverged from its remote's `live` holds a merge that only a
publication makes the remote's own. Left local, that merge is not on the
remote's `live`, so the next upstream update diverges again and is merged again,
at every update, where a store that had published would read as behind and take
it as a fast-forward. A divergence is therefore a tax on every later upstream
update until it is pushed, and the pushing is what ends it: the push prepares
the merge, `/gitlore:resolve` lands it locally, and the rerun push publishes it
and leaves the store on `live`.

Races are not routine, but they must be expected. Git is distributed, so another
checkout can publish between any fetch and any push, and a divergence can appear
during a run that began in sync. The design treats a divergence as an ordinary
state to resolve and publish, not as a fault to prevent.

The only exception to "a divergence names `/gitlore:push`" is a take that is a
fast-forward plus the canned bookkeeping commit.

## Decisions — D75, D76, D86

**D75 — A push publishes each store as soon as it is ready**

A tier repaired inside a push goes to its own remote at once, even when a later
tier or memory then fails and the push as a whole does not finish. The tier is a
store in its own right, with its own remote, and its resolution is good whatever
the stores after it do. A tier merge that a push prepared lands locally, whether
the push ran from `/gitlore:push` or from the `pre-push` hook, and the rerun
push publishes it, tier before memory.

My human partner's call, on the question of pushing tiers as soon as possible
knowing a later tier or memory may fail the push: "That being DVCS, you cannot
rule out races, so yes, expect divergence popping up during operation. And when
tier divergences are resolved, push them as soon as they are ready. That's
important, pushing your divergence is what puts you back on live. Unpushed
divergence has to be remerged at each remote update, instead of fast-forward."
And of `/gitlore:merge`: "Merge is for incoming, no publish."

A tier repair that rests on a root problem is the case the suite pins: the
repaired tier reaches the tier's remote and not memory's
(`tests/push_tier_publication.bats`, "reaches the tier's remote and not
memory's").

**D76 — A divergence names push; merge only when the take is a fast-forward**

The rule is my human partner's: "If there is a divergence, the hint is always
push. Only suggest merge when it is possible to only ff (+canned commit). Why:
divergence makes ff impossible, that's a tax on all future upstream updates. So
push, and after the next local update, hint gitlore:merge to ff."

`/gitlore:merge` is hinted only when the take is a fast-forward plus the canned
bookkeeping commit (D49). `/gitlore:push` prepares the merge for a divergence
and, run again once the merge has landed, publishes the merged result:
`gitlore_reconcile_one` (`scripts/lib/resolve-merge-stores.sh`) for `HEAD`
against local `live`, and the push's divergence path for the remote. After it
the store is back on `live`, the next upstream update reads as older, and the
hint is `/gitlore:merge`, which fast-forwards.

A `HEAD` forked from local `live` is a divergence and hints `/gitlore:push` too,
with or without a remote.

**D86 — Only push publishes; resolve lands locally**

`/gitlore:push` publishes, and a parent `git push` counts as push: its
`pre-push` hook runs the same `gitlore_push_stores`. `/gitlore:merge` publishes
nothing, and `/gitlore:resolve` repairs and lands. A landing, memory or tier and
whoever prepared the merge, ends after the local `HEAD:live` move with
`gitlore: merged without publishing. Run /gitlore:push to publish.` and exit 0;
a refused move exits 1 before that line, leaving what
[merge-and-resolve.md](merge-and-resolve.md) describes. One rerun path serves
every entry: a push that met a divergence is finished by pushing again, and a
remote that moved during a synthesis is met by the next push, which prepares the
next merge.

The default `resolve.sh` run moves no remote ref. It runs each store's local
gate before its remote gate, prepares a merge for a diverged store, and for a
store only ahead prints
`gitlore: <store> is ahead of its remote. Run /gitlore:push to publish it.`,
`<store>` being `memory` or `tier '<name>'`. No skill text chooses a command by
who invoked it, because the script names `/gitlore:push` in every case.

Remotes follow the same rule. Install and add-tier create remotes; push, resolve
and every other entry point create none. A memory store with no remote, or a
placeholder one, stays local by choice and is reported as such with no command
named, since a store without a remote is a decision and not a defect. A tier
with no remote is not treated alike: a push stops on it with exit 1, because a
tier exists to be shared. A wired remote with no `live` gets its first `live`
from `/gitlore:push`.

The rule is my human partner's: only `/gitlore:push` publishes. A landing that
published according to who prepared the merge would make its outcome depend on
who started it.

## Rejected alternatives

**Holding a repaired tier back until memory can record it.** The push would
publish nothing until every store is ready, so a failure in a later store
strands the resolution of an earlier one, and the next run merges it again
(D75).

**Publishing from `/gitlore:merge`.** `/gitlore:merge` is for incoming and
publishes nothing; publishing is `/gitlore:push`, which takes upstream first
under D59 and so already covers a divergence (D75).

**Hinting `/gitlore:merge` for a divergence.** The merge lands but stays
unpublished, so every later upstream update merges again instead of
fast-forwarding (D76).

**Hinting `/gitlore:resolve` for a `HEAD` forked from local `live`.** Resolve
lands the merge and stops, so the divergence it repairs stays unpublished; the
hint names the command that ends it, `/gitlore:push` (D76, D86).

**Resolve publishes what it lands.** A landing's outcome would depend on who
prepared the merge, and a repair run by hand would send commits to a remote the
user only asked to repair locally (D86).

**A no-publish mark on the merge state.** The mark routed every landing by
whoever prepared it, which exists only because resolve sometimes publishes; with
no landing publishing there is nothing to mark (D86).
