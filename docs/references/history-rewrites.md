# History rewrites — decisions D61, D62, D63

What a store's remote publishes when its history is rewritten, and what a clone
still on the old history does about it. Covers the memory store and every tier;
a parent repository is out of scope (D46 already keeps gitlore from rewriting
one, and guarding it would put every project's history in reach of a memory
fix).

- **D61** — a rewritten store publishes a rewrite record: an append-only
  `gitlore/rewrites` branch whose tree is a format version and one flat map of
  every commit id the rewrites changed; the old history stays on an archive
  branch gitlore never fetches
- **D62** — a divergence whose local side holds a recorded old commit is
  refused, naming the crossing script; nothing repairs it automatically
- **D63** — a damaged record is repaired in place by
  `record-rewrite.sh --rebuild`: the readable lines are kept and the result is
  pushed as one fast-forward on the tip it read, leased to that tip, so the
  record is never absent or rewritten

---

## The failure being closed

A rewrite gives most commits new ids, but the old and new histories still share
the unchanged prefix, so they are related. To every gate that reads ancestry, a
clone still on the old history looks like an ordinary divergence: neither tip
contains the other. `/gitlore:merge`, `/gitlore:push` and a parent `pre-push`
all reach `gitlore_yield_merge`, which prepares a clean merge — both sides made
the same changes since the base — and directs the agent to finish it without
asking (D9, D24). The merge commit carries the old tip as its second parent, and
the next push publishes it. One forgotten clone, on any machine, undoes the
rewrite and doubles the history.

Ancestry cannot tell a rewrite from a divergence, so the information has to come
from whoever did the rewrite, published where every clone already looks.

## The record — D61

**D61 — A rewritten store publishes an append-only rewrite record**

`gitlore/rewrites` on the store's own remote. Its tree holds two files:

- `version` — the format version, `1`.
- `map` — one line per rewritten commit, `<old id> <new id>`, each id as long as
  the store's object ids: 40 hex digits for a sha1 store, 64 for sha256, read
  from `git rev-parse --show-object-format`. A commit whose id the rewrite left
  unchanged has no line; a commit the rewrite dropped maps to zeros of that
  length. The format version stays `1`: the length is a property of the store,
  not of the record.

Each rewrite appends its lines to `map` in a new commit on top of the previous
record, so the branch only ever fast-forwards and the record itself is never a
rewritten ref. Lines are never edited: a commit rewritten twice has two lines,
and a lookup follows them until an id has no line of its own. The map is read
whole, on the divergence path only, which is rare; at a few hundred lines per
rewrite that costs nothing worth indexing.

The old tip goes on a separate `gitlore/archive/<date>` branch, pushed before
the force-push. It keeps every old gitlink and every old release tag fetchable,
and it is not part of the record: a fresh clone that fetched the record would
otherwise fetch a second copy of the history. gitlore's own fetches name their
refs, so no gitlore command brings an archive into a clone; a plain `git clone`
or `git submodule update --init` takes every branch and does. Deleting an
archive branch, once every known clone has crossed, is the owner's call.

The record is written by
`scripts/record-rewrite.sh <store> <commit-map> [<remote>]` from
`git filter-repo`'s `commit-map`, which lists every commit with its old and new
id. It runs on the rewritten repository, bare or not — a rewrite is done on a
`--mirror` clone, which filter-repo leaves without `origin`, so that run names
the remote as the third argument. The script keeps the changed lines, skips any
the record already holds, appends the rest and pushes the record with a plain
push, before the rewrite's own force-push. An old id the record already maps to
a different new id is refused whole: it is a second rewrite of the same history
from another mirror, and a genuine second rewrite starts from the first one's
new ids, so it never collides. The archive branch is pushed separately.

## Detection and crossing — D62

**D62 — A divergence on recorded old history is refused, naming the crossing
script**

### Detection

At `gitlore_yield_merge`, before any merge is prepared, a yield whose authority
is the remote's `live` fetches the record. A yield against the local `live`
skips the check and needs no network: when `HEAD` and `live` both sit on old
history, `live..HEAD` holds no recorded commit, and the old history can only
reach the remote through a remote-authority yield, which takes the check. An
absent record is the ordinary case — no rewrite ever happened — and the merge
proceeds as before. Otherwise every commit reachable from the local side and not
from the remote is looked up as a key in `map`; one hit means the local side
sits on superseded history, and the yield refuses instead of preparing.

A record that exists but cannot be fetched refuses too: proceeding would be the
re-import the record exists to prevent, and a fetch failure on the divergence
path is visible to the user and retried by running the command again.

SessionStart's divergence report takes the same test, so the first word a clone
on old history gets names the crossing rather than `/gitlore:merge`.

### Crossing

The refusal names `scripts/cross-rewrite.sh <store>`, which crosses one store
and is run by hand: it maps `HEAD`, `live` and `main` through the record,
following each id's chain until it has no line, and refuses a ref whose chain
ends in a dropped commit. It requires each new commit's tree to match the old
one's — modulo gitlinks, which it maps through the child store's record — checks
the new commits out and stages the store's gitlink in its parent. Children cross
before parents, the same order the merge and push loops already take, so a
parent's gitlinks always have a crossed child to point at.

A store with local-only commits on top of the old history is refused by the
script too, which names the base (the newest recorded commit under them) and
prints the commands that replay them onto its mapped id; run again, the script
finds the ref on the new history and has nothing to do. A ref holding no
recorded commit but sharing history with the remote's `live` is already crossed,
local commits or not; one sharing none is refused. The preconditions of a
rewrite — every clone publishes first — keep that case off the known clones; it
exists for the ones nobody remembered.

Every refusal ends in the act that resolves it. A dropped commit prints the move
of the ref to the remote's tip for a ref with no local work, and the `git log`
that lists the work to replay first for one with some. A ref on neither the
remote's history nor a recorded commit prints the `git log` that compares it
with the remote and says a person decides, and so do trees that differ outside
gitlinks (`git diff --stat`) and a gitlink the child's record maps elsewhere
(`git diff-tree`): the record may be wrong, or the rewrite may have meant to
change them. A mapped commit the clone lacks is fetched from the remote's `main`
first, since it can be published there before `live` carries it; when it is
still absent, the rewritten history has not reached the remote, and the refusal
says to run the script again once the force-push has landed, since a run fetches
`live` and `main` itself. It never prints a rebuild, because the record may be
right.

A record that cannot be read — no version file, a version that is not a number,
no map, a map line that is not a pair of ids, a chain that does not end — prints
the rebuild (D63). The commit-map is the one input a crossing clone cannot have:
only the rewritten mirror holds it, as `filter-repo/commit-map`. With `MIRROR`
set to that mirror, the refusal prints
`scripts/record-rewrite.sh --rebuild "$MIRROR" "$MIRROR/filter-repo/commit-map" <origin url>`,
with the origin's URL made absolute, since the command runs from another
directory. A remote with no record prints the same command without `--rebuild`.
A version that is an integer above 1 says to update gitlore. A store that is not
checked out prints the `git submodule update --init` that checks it out, run
from the repository holding its gitlink, with one step per path component that
is not checked out, outermost first: a tier whose memory store is absent
initializes the store before the tier. A git that cannot report the object
format fails with its own message.

The guard protects a clone only once that machine runs a gitlore release
carrying it, so a rewrite's force-push follows the release and the plugin update
on every machine that holds a clone.

## Repairing a damaged record — D63

**D63 — A damaged record is repaired in place by `record-rewrite.sh --rebuild`**

A record can be damaged: a version file that is missing or is not a number, a
map that is missing, a line that is not a pair of ids, or a line that closes a
chain loop. The plain run refuses to append to such a record. With `--rebuild`
the script keeps every line of the remote's map that is a pair of ids and does
not close a chain loop, in order, so earlier rewrites survive; drops the others
and reports their line numbers, never their content; writes version 1; merges
the commit-map the way the plain run does; and pushes one commit whose parent is
the tip it read. That is a fast-forward, so the record is never absent from the
remote and never rewritten. The push carries a lease pinned to the sha the run
read (an empty lease, meaning the ref must not exist, when it read none), so it
can overwrite nothing but that sha: a record that moved forward or sideways, was
rolled back to an earlier commit, or was deleted since the read is refused. A
trailing carriage return on a map line is stripped before parsing, so a map
saved with CRLF endings keeps its lines. A record of a newer version is refused:
its lines may mean something this script does not know. On a healthy record the
flag changes nothing.

The repair needs the commit-map of the rewrite being recorded, which only the
rewritten mirror holds, and a line it cannot parse is lost: the repair restores
the record's shape, not information the damage destroyed.

## Rejected alternatives

**Delete the damaged record and record it again.** The refusal could print a
`git push --delete gitlore/rewrites` followed by a plain run. Between the two
the remote has no record, which every clone's divergence check reads as the
ordinary case of no rewrite, so a merge proceeds and re-imports the old history;
a delete with no lease removes a tip another rewrite appended meanwhile; and a
plain run starts from an empty map, losing every earlier rewrite's lines unless
each rewrite's commit-map is still at hand.

**A plain push of the rebuilt commit.** The remote accepts a child of the tip
the run read whenever its ref is that tip, an ancestor of it, or absent. A
record rolled back to an earlier commit, or deleted, between the read and the
push is a deliberate act by someone else, and a plain push silently undoes it.
The lease closes both and costs nothing: it is pinned to the sha the run read
and the pushed commit descends from that sha, so it is strictly tighter than the
plain push.


**No guard.** Rewrites are rare, and a careful owner crosses every clone by
hand. But the failure is silent and propagates — the tooling merges and
publishes without asking — and the clones that matter are exactly the ones
nobody remembered, such as a second machine's.

**An automatic crossing at the yield.** The refusal could repoint and replay
instead, translating each replayed commit's gitlinks through the child's map. It
is the complex half of the mechanism and serves only a clone that had
unpublished commits when the rewrite landed, which the rewrite's preconditions
exist to prevent. The versioned record leaves room for it if a second rewrite
shows the need.

**Matching commits without a map.** Whole-tree equality matches a tier, which
holds no gitlinks, but not the memory store, whose trees differ in the tier
gitlink; equality modulo gitlinks needs the child's map anyway. Walking both
histories from the shared prefix, pairing commits by mapped parents and equal
dates, is exact only while the rewrite keeps every commit — dropping the empty
commits a file removal leaves breaks it.

**A path-keyed map.** One entry per old id at a fanned-out path, so a lookup
reads a few small tree objects instead of the whole map. It buys speed on the
one path that is rare, and its cumulative form rewrites most of the fan-out
directories on every event.

**An external cache.** A sqlite index over the record, answering the lookup
without reading it. A dependency the store does not otherwise have, and an
invalidation problem in exchange for a read that is already cheap.

**A record force-pushed as a single commit.** Simpler history, but then the
record is itself a rewritten ref, and needs the guard it feeds.

**The old tip as a parent of the record.** One ref instead of two, but every
clone fetching the record would fetch the whole old history with it.

**Guarding the parent repository.** The same record could cover a parent's
rewrite, but a parent is a project's own history and a memory fix has no
business reaching it; a parent rewrite stays its owner's manual act.
