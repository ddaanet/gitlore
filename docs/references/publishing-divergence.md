# Publishing a divergence — decisions D75, D76, D84

Why a divergence is published rather than carried, and what the position report
hints because of it: a push publishes each store as soon as it is ready (D75),
and the position line names `/gitlore:push` for any divergence, `/gitlore:merge`
only for a take that is a fast-forward (D76), one line for every store (D84).
The first two share one argument. The divergence path they sit on,
`gitlore_reconcile_one` and the prepared merge, is in
[merge-and-resolve.md](merge-and-resolve.md); what `live` is and which side of a
merge is authoritative are in [branch-model.md](branch-model.md).

- Publishing — **D75** a push publishes each store as soon as it is ready, and
  `/gitlore:merge` is for incoming and publishes nothing · **D76** a divergence
  names `/gitlore:push`; `/gitlore:merge` is named only for a fast-forward take
  · **D84** SessionStart reports every store's position in one line

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

`SessionStart` moves no module (D59). A module is the memory store or a tier. It
clones one that is not materialized, at the commit memory records
(`submodule update --init`, so "clone the repo and run claude" works), fetches
read-only, once, under a timeout (`GITLORE_FETCH_TIMEOUT` seconds, default 5;
D83), and reports; every report names a command that works when followed, and
nothing is fixed silently. A store is detached; one attached to a branch breaks
a precondition that install and the mount establish and gets no handling. A
missing local `live` is normal on a fresh clone. SessionStart makes memory's
from `HEAD`; a tier's is not made there, and the tier reads as `live` at `HEAD`
until a push, a memory commit or `/gitlore:resolve` makes it.

| State | Report |
|---|---|
| Not materialized | Cloned at its recorded commit; a failed checkout is named, and the agent is told the tier's facts are unavailable and its root lines stay |
| Mid-merge | Tier: its notice alone, naming `/gitlore:resolve`. Memory: the command that lands the prepared merge and the one that aborts it, `resolve.sh continue-after-merge` and `abort-merge`; a merge with no `MERGE_HEAD`, or a state file without its briefing, names `/gitlore:resolve` and `abort-merge` instead |
| Recorded commit no repository holds | The unresolvable-pin report ([unresolvable-pin.md](unresolvable-pin.md)) |
| Local against the authority's `live` | The position line below |
| Root's tier lines would change in a compose pass | The pending report, `gitlore-compose`; a tier off its pin is refused in it, naming `/gitlore:merge`, or yielded where that take refuses for uncommitted changes |
| A tier's index holds a line root does not | The orphan report, reported and never refused |

A prepared merge moved `HEAD` onto its authority, so a position read would
describe the preparation: a mid-merge module reports the notice alone.

### The position

After a successful fetch, each module compares what it holds locally, `HEAD` and
local `live`, with the authority's `live`, not with the pin. The authority is
the remote's `live` when the fetch brought it, and local `live` otherwise, which
covers no remote, a failed fetch and a remote with no `live` yet. The table
stands against local `live` too, memory and tier alike
(`gitlore_module_position`).

| Local against the authority's `live` | Word in the line | Command |
|---|---|---|
| Strictly behind | `N behind` | `/gitlore:merge`, which fast-forwards and needs no push |
| Strictly ahead | `N ahead` | `/gitlore:push` |
| Diverged | `diverged` | `/gitlore:push`, which reconciles and publishes; a rewritten history instead leaves the store out of the line and names the crossing script ([history-rewrites.md](history-rewrites.md)) |
| `HEAD` forked from local `live` | `diverged` | `/gitlore:push`, which prepares the merge, whatever the authority and with or without a remote |
| In sync | `in sync` | none |

When local `live` is itself the authority and `HEAD` is behind it, the store
reads `N behind` and the line names `/gitlore:merge`, counting what `HEAD`
lacks; a dirty memory store is listed the same way, and says only that it is
dirty beside the line, since a take will not move a dirty `HEAD`.

A failed fetch keeps its could-not-fetch message, with git's reason, ahead of
the position line, on the user channel only because git's stderr can carry text
the remote chose; the agent gets a fixed sentence saying the user has it. A
fetch that outlives the timeout is killed and its message says
`timed out after <n>s` in place of git's reason: memory's on both channels,
since the text holds nothing the remote chose, a tier's on the user channel. The
store is listed `unreachable` in the line in place of its local position. No
remote adds no message.

The pin takes no part: a parent `git pull` over unpublished memory reads as
diverged, and over none as behind. Being ahead of the pin says nothing, so
memory published before the parent commit that records it reads as in sync.

The only exception to "a divergence names `/gitlore:push`" is a take that is a
fast-forward plus the canned bookkeeping commit.

## Decisions — D75, D76, D84

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

**D76 — A divergence names push; merge only when the take is a fast-forward**

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

**D84 — SessionStart reports every store's position in one line**

One line, `gitlore: Run /gitlore:push (memory in sync; ddaanet diverged)`, or
`gitlore: memory in sync; ddaanet in sync` when no command is named, goes out
once on `systemMessage` and `additionalContext`, the same text, the all-in-sync
form included. A line listing one store has no separator. It stands as its own
paragraph on both channels and after any fetch-failure message of its run.
Stores come in order: `memory`, then each tier by name in `.gitmodules` order,
bare and unquoted.

The words are a closed set: `in sync`, `N ahead`, `N behind`, `diverged`,
`unreachable`, N never 0. `diverged` is position `forked` or `diverged` from
`gitlore_module_position`. `N ahead` counts the commits the store holds, `HEAD`
or local `live`, whichever is further, that the authority lacks. `N behind` is
measured from the checkout: the commits of the authority that `HEAD` lacks, or
when `HEAD` lacks none, those local `live` lacks, so a tier whose local `live`
equals `origin/live` and is two commits ahead of its `HEAD` reads `2 behind`.
`unreachable` is a failed fetch other than "couldn't find remote ref" or no
remote; it replaces whatever the local position is and names no command, and its
fetch-failure message keeps its text and channels.

The command is `/gitlore:push` when any listed store is `N ahead` or `diverged`,
else `/gitlore:merge` when any is `N behind`, else none. The rule is D76's taken
over every listed store: any divergence is published.

A store whose state has its own message and for which no push or merge is named
is left out and keeps that message: a memory store holding a merge, a tier with
an unfinished merge or that could not be checked out, a diverged store whose
rewrite check hit a recorded rewrite or could not run. A store with a lost pin
keeps its report and is listed with its position. With every store left out, no
line is printed. `memory — uncommitted changes present.` stays beside the line.

*One position line per store* (D59's form) names a command per store, and two
stores can name different ones. *Hint wording that tells `HEAD` diverged from
`live` from a divergence from the remote* (D76's text) is detail the command
does not use: both name `/gitlore:push`. *A diagnostics paragraph telling the
user to run `/gitlore:merge` for tiers whose local `live` is ahead of `HEAD`*
could name a command other than the line's, so those tiers are counted
`N behind` and the pending-compose report is withheld for them.
*A status word carrying more than a position* (`dirty`, `mid-merge`) mixes
states that name no push or merge into a set that decides the command.

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
