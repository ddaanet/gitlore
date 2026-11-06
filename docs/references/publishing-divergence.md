# Publishing a divergence — decisions D75, D76

Why a divergence is published rather than carried, and what the position report
hints because of it: a push publishes each store as soon as it is ready (D75),
and a module's report hints `/gitlore:push` for any divergence, `/gitlore:merge`
only for a take that is a fast-forward (D76). The two share one argument. The
divergence path they sit on, `gitlore_reconcile_one` and the prepared merge, is
in [merge-and-resolve.md](merge-and-resolve.md); what `live` is and which side
of a merge is authoritative are in [branch-model.md](branch-model.md).

- Publishing — **D75** a push publishes each store as soon as it is ready, and
  `/gitlore:merge` is for incoming and publishes nothing · **D76** a divergence
  hints `/gitlore:push`; `/gitlore:merge` is hinted only for a fast-forward take

---

## The argument

**Pushing your divergence is what puts you back on `live`.** A store whose
history has diverged from its remote's `live` holds a merge that only a
publication makes the remote's own. Left local, that merge is not on the
remote's `live`, so the next upstream update diverges again and is merged again,
at every update, where a store that had published would read as behind and take
it as a fast-forward. A divergence is therefore a tax on every later upstream
update until it is pushed, and the pushing is what ends it: the push lands the
merge, publishes it, and leaves the store on `live`.

Races are not routine, but they must be expected. Git is distributed, so another
checkout can publish between any fetch and any push, and a divergence can appear
during a run that began in sync. The design treats a divergence as an ordinary
state to resolve and publish, not as a fault to prevent.

## What a module reports

After a successful fetch, each module (memory, and each checked-out tier)
compares what it holds locally, `HEAD` and local `live`, with the authority's
`live`, not with the pin. The authority is the remote's `live` when the fetch
brought it, and local `live` otherwise, which covers no remote, a failed fetch
and a remote with no `live` yet. The report is one line per module:

- Local strictly newer than the authority: hint `/gitlore:push`.
- Local strictly older: hint `/gitlore:merge`.
- Equal: `in sync.`, and nothing else.
- Diverged: hint `/gitlore:push`.
- `HEAD` forked from local `live`: hint `/gitlore:push`, whatever the authority
  and with or without a remote.

A failed fetch keeps its could-not-fetch line, with git's reason in front of the
position line. No remote adds no line. The pin takes no part: memory published
before the parent commit that records it reads as in sync, and a parent
`git pull` over unpublished memory reads as diverged.

## Decisions — D75, D76

**D75 — A push publishes each store as soon as it is ready**

A tier repaired or merged inside a push goes to its own remote at once, even
when a later tier or memory then fails and the push as a whole does not finish.
The tier is a store in its own right, with its own remote, and its resolution is
good whatever the stores after it do. The same holds for a tier merge landed
inside the `pre-push` hook mid-loop: it publishes on landing.

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

**D76 — A divergence hints push; merge only when the take is a fast-forward**

The rule is my human partner's: "If there is a divergence, the hint is always
push. Only suggest merge when it is possible to only ff (+canned commit). Why:
divergence makes ff impossible, that's a tax on all future upstream updates. So
push, and after the next local update, hint gitlore:merge to ff."

`/gitlore:merge` is hinted only when the take is a fast-forward plus the canned
bookkeeping commit (D49). `/gitlore:push` prepares the merge for a divergence
and publishes the merged result: `gitlore_reconcile_one`
(`scripts/lib/resolve-merge-stores.sh`) for `HEAD` against local `live`, and the
push's divergence path for the remote. After it the store is back on `live`, the
next upstream update reads as older, and the hint is `/gitlore:merge`, which
fast-forwards.

A `HEAD` forked from local `live` is a divergence and hints `/gitlore:push` too,
with or without a remote.

## Rejected alternatives

**Holding a repaired tier back until memory can record it.** The push would
publish nothing until every store is ready, so a failure in a later store
strands the resolution of an earlier one, and the next run merges it again
(D75).

**Keeping a tier merge landed inside the `pre-push` hook unpublished.** The same
unpublished resolution under another entry point; it is remerged at each remote
update instead of fast-forwarded (D75).

**Publishing from `/gitlore:merge`.** `/gitlore:merge` is for incoming and
publishes nothing; publishing is `/gitlore:push`, which takes upstream first
under D59 and so already covers a divergence (D75).

**Hinting `/gitlore:merge` for a divergence.** The merge lands but stays
unpublished, so every later upstream update merges again instead of
fast-forwarding (D76).

**Hinting `/gitlore:resolve` for a `HEAD` forked from local `live`.** On a
memory with no remote, `/gitlore:resolve` first tries to create a remote, which
with an authenticated `gh` is a GitHub repository, and prepares no merge. The
`head-vs-live` merge is prepared inside the push (D76).
