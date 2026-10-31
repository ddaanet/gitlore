# Git hooks — decisions D46, D50

The git hook that publishes memory inside a parent git operation, and the
invariant binding the gitlink a parent commit records to memory's `live`. A
parent commit runs no gitlore hook: `commit-memory.sh` is the one commit path
(D58, in [memory-commit-ownership.md](memory-commit-ownership.md)), and it,
`push-memory.sh` and the `push` skill are in
[memory-entry-points.md](memory-entry-points.md), which also holds the shared
bodies — `gitlore_sync_memory_to_live` and `gitlore_push_stores` — the scripts
and the hook call. The approval gate the commit path carries out is in
[commit-gate.md](commit-gate.md); FR11 itself stays in `design.md`.

- The pointer — **D46** a parent commit is never rewritten to re-pin memory; a
  push refused by divergence is resolved and pushed again
- The commit path — **D50** the store is composed before it is committed; a pin
  refusal is fatal, and so is a compose problem in an index file the commit
  changes, while every other compose refusal is reported

---

## Mechanism

### The git hook

The parent repo's chain carries one gitlore hook, `pre-push`. A parent commit
runs none, so it never touches memory: the commit path stages the memory gitlink
in the parent index, and the commit records what is staged (D58). `pre-push`
begins by clearing git's full local-env-var set
(`git rev-parse --local-env-vars`). Git exports those variables scoped to the
*parent*, and a `git -C <submodule>` that inherits them breaks submodule
resolution or, in a linked worktree, silently redirects the submodule's refs and
objects into the parent's store. It exits 0 when the repo has no memory
submodule entry, and when the submodule worktree is absent (a session-less
linked worktree) — never block a parent git operation over memory. Its refusals
branch on `$CLAUDECODE`: agent-facing text naming the next action, user-facing
text directing them to open the project in Claude Code.

**`pre-push`** publishes in a before-and-alongside order: each tier's `live` to
its own remote, then memory's. Failure is fatal — a tier that silently stops
publishing is indistinguishable from one with nothing to say. The memory-absent
skip stays non-blocking but warns when the gitlink about to be published is not
reachable on the memory remote, decided locally without a fetch. Divergence
routes to `/gitlore:resolve`, which diagnoses the flavor.

### The gitlink and `live`

**The gitlink a parent commit records is memory's `live` itself or an ancestor
of it, except after a commit that forked from `live`.** `commit-memory.sh` makes
it `live` itself when the commit fast-forwards `live`: after a commit that moved
memory's HEAD it stages memory's HEAD, which is the commit it just advanced
`live` to. When `live` holds commits the new commit lacks, the staged HEAD is
not an ancestor of `live` until `/gitlore:merge` or `/gitlore:push` prepares and
lands the head-vs-live merge. The staging is skipped during a rebase,
cherry-pick or revert, where a replayed commit keeps the pointer it recorded.
Every other path that advances memory — the `/gitlore:merge` (its local move of
`HEAD` onto `live` included), a resolved merge — moves `live` forward and leaves
the gitlink behind as an ancestor; a `head-vs-remote` merge in particular keeps
the pending commit reachable as its second parent (D6). A gitlink behind
memory's HEAD is therefore the resting state — ` M memory` in the parent's
porcelain — not drift: it floats between parent commits, the next one records
the move, and nothing walks memory back to it. `SessionStart` runs
`submodule update` on memory only when its worktree is absent; the
pin-to-the-gitlink discipline (D43) is for tiers inside memory, not for memory
in the parent.

The invariant is what NFR5 rests on at publish time: the reconcile that precedes
`gitlore-push` lands a head-vs-live merge first, which keeps the staged commit
reachable as its second parent, and it survives any number of merge rounds.
`pre-push` runs no reconcile: its preflight refuses a store whose HEAD and
`live` have forked and sends the user to `/gitlore:resolve`. A push of `live`
publishes every ancestor, so `origin/live` contains the gitlink the moment that
push succeeds, and `pre-push` orders memory before the parent, so a parent push
that goes through implies its gitlink is public. A push refused by divergence is
therefore resolved and pushed again, however many times `origin/live` moves
while a merge is under review; the parent commit — tagged or not — is never
rewritten to name the merged memory (D46).

## Decisions — D46, D50

Why a parent commit whose push was refused is never amended to catch up with
memory, what the commit path does about a stale carrier before it commits, and
which failures leave the approved summary standing.

**D46 — A parent commit is never rewritten to re-pin memory; a push refused by
divergence is resolved and pushed again**

The case that raised it is a release: a toolkit's `release` recipe commits a
version bump — recording the memory pointer `commit-memory.sh` staged — tags it,
and pushes. `pre-push` publishes memory first, and if any store's `origin/live`
moved since the commit it prepares a merge and refuses, leaving the commit and
tag local. The window is human-paced — the FR11 approval on the release commit
and the review of the merge both sit inside it — and it reopens whenever
`origin/live` moves again while a merge waits for review, so the refusal can
repeat.

The considered repair was to `commit --amend` the release commit after the merge
lands so its gitlink names the merged memory, then `tag -f`. It is refused
because the invariant above already gives correctness: the recorded commit is
the merge's second parent, it is published by the first `live` push that
succeeds, and NFR5 holds without the tag's tree ever naming the merge. What the
amend buys is coherence — a tag whose tree names the memory as merged, and a
clean parent tree immediately after — and it costs a scripted rewrite of a
tagged commit, a forced move of a tag about to be published, and an ordering
dependency on the stale-merge guard, which holds the memory commit path until
the merge is resolved. The loop that replaces it — resolve, push again, until
the push lands — is the one the `push` skill already runs (D20), and a gitlink
behind memory's tip is the same resting state every other memory advance leaves.

**D50 — The commit path composes before it commits; a pin refusal, or a compose
problem in an index file the commit changes, is fatal**

Composition otherwise runs from the session surfaces alone, so a carrier left
stale by a missed in-session compose self-heals at the next `SessionStart` but
**ships** if a memory commit lands first — and the carrier is what a tier's
remote serves. `gitlore_sync_memory_to_live` composes before it commits, and
ahead of `gitlore_sync_tiers_to_live`: composition writes carrier files inside
the tiers, so a later pass would pin every gitlink to pre-compose content.

**Dirty stores only.** Composing a clean store manufactures a dirty state no
approved summary covers, and the gate would refuse the commit for a change the
agent never made. A committed carrier already diverging from the committed root
index waits for `SessionStart`, whose compose rides the next commit that has a
summary. This holds the FR11 boundary: a carrier projects root index lines an
approved summary already covered, never new content.

**The two refusals are not interchangeable, and what separates them is what
committing past one destroys or publishes.** A `gitlore_compose_check` refusal
withholds a projection and destroys nothing, so what committing past it risks is
publishing the problem, and only a file the commit changes can do that. A
duplicate, interleaved or welded line in an index file with uncommitted changes
— root's `MEMORY.md` or a tier carrier — aborts: the output lists every changed
index file with a problem, and the agent is told to edit the named lines and
retry, the summary needing approval again. Compose rc 1 writes nothing, so what
reads as changed is the same before and after it. The same problem in a file
with no uncommitted changes — a tier dirty only outside its carrier included —
is not what this commit carries, and the manifest and leftover-prefix rules name
no index file; all of those are reported and the commit goes ahead. The line
this draws is the one D52 ([tier-arrival-repair.md](tier-arrival-repair.md))
builds on: the wording of an index a tier publishes is upstream's to change, and
a structural defect that arrives anyway — from a hand push, or an older gitlore
— is the take's to repair. Proceeding past a `gitlore_compose_check_pins`
refusal instead lets this function's own `add -A` adopt the moved gitlink and
remove the condition it refused on: the next compose projects root's older text
over the carrier with nothing left to refuse, `gitlore_sync_tiers_to_live`
commits that inside the tier, and `pre-push` ships it to the tier's own remote,
so the approved upstream fact is destroyed one commit after the warning. The pin
check therefore runs ahead of compose and aborts, naming no remedy of its own —
every branch of `gitlore_compose_check_pins` prints the one its own cause takes,
and a single abort can carry several tiers with different causes. A write
failure aborts too — a half-written carrier must not be committed.

**A tier merely ahead of its pin is put back on it, and the take adopts from
there.** A clean tier whose local `live` contains its `HEAD` has nothing to
lose: every commit `HEAD` holds is reachable from `live`, so
`gitlore_compose_check_pins` checks it out at the pin — the commit the memory
store's index already records, and the one `submodule update` would restore at
the next `SessionStart` — and what is left is exactly the state
`gitlore_adopt_advanced_live` takes, a clean tier on its pin with `live` ahead
of it. The refusal stands over that, with `/gitlore:merge` as its remedy,
because the root index still has to take the carrier before any pass composes
down onto it, and that adoption is the tooling's: compose the carrier up, stage
the pair (D43). Two states are left where they are. A dirty tier, because the
checkout would carry work no approved summary covers onto the pin and the take
refuses a dirty store in any case. And a tier whose `live` is short of `HEAD`,
where the checkout would strand the commits `HEAD` alone holds; its remedy is
the ff-checked `push . HEAD:refs/heads/live` — the move
`gitlore_repair_stranded_live` makes wherever it runs — after which the guard
returns the tier to its pin and the take adopts, and a push refused as a
non-fast-forward is a divergence for `/gitlore:resolve`. A checkout that fails
leaves the tier untouched and reports git's own words with the command that
finishes the return.

**A retry that skips the take commits, and that residual is accepted.** Once the
guard has returned a tier to its pin nothing refuses: the tier is clean and on
the commit the store records, so a retried commit that does not run
`/gitlore:merge` first composes and commits normally while the arrival stays in
the tier's local `live` alone. Nothing is lost — `live` holds every arrived
commit and the guard's message names the take as the next command. The cost
lands later: the next commit to that tier is made on the pin, its `HEAD:live`
advance from `gitlore_sync_tiers_to_live` is refused as a non-fast-forward and
reported as a fork, and the next `/gitlore:merge` or `/gitlore:push` reconcile
prepares a `head-vs-live` merge that `/gitlore:resolve` lands. A skipped take
therefore costs one merge later, never a fact.

**A tier commit the run could not record is adopted on the retry.** The tier
commit moves the tier's HEAD, and only memory's later `add -A` stages the moved
gitlink. A transient `index.lock` between the two — or a tier `live` that cannot
advance, or a killed run — leaves the tier ahead of its pin, the shape the pin
check refuses, and a retried commit would be refused for good.
`gitlore_sync_tiers_to_live` therefore writes a landing record into the tier's
gitdir just before each commit — the commit the tier sits on — and removes it
when the commit fails or once `add -A` has staged every gitlink. Ahead of the
pin check, `gitlore_stage_landed_tiers` stages the gitlink of any tier whose
HEAD's parent is the recorded commit and still the pin. That overwrites nothing:
the commit path composed that carrier from the root index just before committing
it. The residual is a run killed between writing a record and its commit
failing, followed by a commit made on the same pin by other means.

**Staging a moved gitlink without projecting up first inverts that guard.**
Staging alone returns the enclosing index to agreement with the tier's HEAD —
the disagreement the pin check reads — so nothing is left to refuse and the next
down projection writes root's older text over facts root has never seen. Every
path that adopts a tier ahead of its pin therefore composes the carrier up into
the root index first and stages the pair, or stages nothing at all; the adoption
a recovered merge owes is one of them
([merge-state-recovery.md](merge-state-recovery.md)). A take that stages nothing
also returns the tier to its pin, keeping what arrived — or the take's repair of
it (D52) — in its local `live` for the next take to adopt, and so does a landed
merge continuation that stages nothing, onto a pin the merge contains once its
local `live` holds the merge; a yield, a pin off to the side and a `live` short
of the merge leave the tier where it is ([tier-stores.md](tier-stores.md)). The
one exception to composing up is a tier commit the commit path itself made,
whose carrier root already describes, so there is nothing to project up.

**A successful compose here stays silent**, by argument rather than omission: on
rc 0 the result is discarded, so a commit that repairs a stale carrier says
nothing. A non-empty result here does mean the in-session compose was missed,
and one `[ -n … ]` test would say so — but the in-session `PostToolBatch` report
is the intended surface for that news, and repeating it puts a line on every
commit that repairs anything, most of which the session has already seen.

## Rejected alternatives

**Amending a tagged parent commit to re-pin memory after a `pre-push` merge.**
Buys only that the tag's tree names the merged memory; the recorded commit is
already an ancestor of `live` and public on the first successful push. Costs
`tag -f` on an unpublished tag, a rewrite of a tagged commit, and a sequencing
dependency on the stale-merge guard (D46).

**A refusal that instructs the agent to run compose.** Composition needs no
judgement, so a gate that stops and asks for it is overhead the harness should
absorb instead (NFR4, D50).

**Reporting an off-pin tier and committing through it.** The commit's own
`add -A` adopts the moved gitlink, so the report is followed at the next compose
by exactly the silent overwrite it warned about (D50).

**Recognising gitlore's own landed tier commit by its message.** Needs no state,
but a session that edits memory while the retry is still blocked approves a new
summary, the landed commit stops matching it, and the tier is refused for good
(D50).

**Staging each tier gitlink right after its commit.** Narrows the window without
closing it: the staging is itself a write to memory's index, so the `index.lock`
that stops `add -A` stops it too (D50).

**Composing a clean store.** A carrier diverging from a committed root index
would be repaired at once, but the compose leaves a dirty state no approved
summary covers, and the gate refuses the commit for a change the agent never
made. `SessionStart` repairs it instead, riding the next commit that has a
summary (D50).

**Reporting a non-empty commit-path compose.** It would say that the in-session
compose was missed, but the in-session `PostToolBatch` report is the surface for
that news, and repeating it puts a line on every commit that repairs anything,
most of which the session has already seen (D50).

**A blanket refusal for every tier ahead of its pin.** One message for the whole
branch, with no state to establish and no store touched by a check. Its remedy
had to be a hand rebuild of the root index's block for the tier followed by
staging the gitlink — the adoption every other path performs mechanically, asked
of a reader in prose, with a silent overwrite as the cost of getting the order
wrong. The state it refused is one checkout away from the one the take already
handles, and that checkout discards nothing (D50).

**Adopting inside the pin guard rather than directing to `/gitlore:merge`.**
Would finish the job in one pass instead of two. But the guard runs from every
compose — `SessionStart`, `PostToolBatch`, the commit path — and adoption writes
the root index and stages a gitlink, which inside a check would land work no
approval covers in the next approved commit. The take owns that adoption
together with its failure handling: the walk-back, the arrival repair (D52), the
canned bookkeeping commit (D49). What the guard does instead is the one move
that writes no index and needs no approval — a checkout to the commit the store
already records (D50).

**Refusing the commit while a tier's local `live` is ahead of its pin.** Would
close the skipped-take residual by making the take mandatory before any memory
commit. But `live` ahead of a clean, on-pin tier is also the resting state
between an arrival and its take, and a refusal there blocks an approved commit
over work that commit does not touch, for a cost the divergence path already
absorbs with nothing lost (D50).

**Leaving a tier whose adoption failed ahead of an unstaged pin.** Nothing is
staged, so the root index is not composed over, but the pin guard then refuses
every memory commit until `SessionStart` walks the tier back, and a take
meanwhile finds nothing to take, the arrival being contained in the tier's HEAD.
Walked back to the pin with the arrival kept in its local `live`, the tier is in
the shape the next take adopts (D50).
