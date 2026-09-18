# Git hooks — decisions D46, D50, D53, D54

The two git hooks that commit and publish memory inside a parent git operation:
what each does in order, what makes them stand down, and the invariant binding
the gitlink a parent commit records to memory's `live`. The callable entry
points that do the same work with no parent commit or push in flight —
`commit-memory.sh`, `push-memory.sh` and the `push` skill — are in
[memory-entry-points.md](memory-entry-points.md), and the shared bodies these
hooks call, `gitlore_sync_memory_to_live` and `gitlore_push_stores`, are
described there. The approval gate `pre-commit` carries out is in
[commit-gate.md](commit-gate.md); FR11 itself stays in `design.md`.

- The pointer — **D46** a parent commit is never rewritten to re-pin memory; a
  push refused by divergence is resolved and pushed again
- The commit path — **D50** the store is composed before it is committed; a pin
  refusal is fatal, and so is a compose problem in an index file the commit
  changes, while every other compose refusal is reported
- The approval after a failure — **D53** the stale-merge guard's report-only
  arms do not restamp it, the guard not saying which arm failed; **D54** a
  restamp that blesses a write another session made mid-run is an accepted
  residual

---

## Mechanism

### Git Hooks

Both hooks run in the parent repo's chain, and both begin the same way: capture
`GIT_INDEX_FILE` and any replay state, then clear git's full local-env-var set
(`git rev-parse --local-env-vars`). Git exports those variables scoped to the
*parent*, and a `git -C <submodule>` that inherits them breaks submodule
resolution or, in a linked worktree, silently redirects the submodule's refs and
objects into the parent's store. Both exit 0 when the repo has no
`gitlore-memory` entry, and when the submodule worktree is absent (a
session-less linked worktree) — never block a parent git operation over memory.

**`pre-commit`** commits memory and moves the pointer, in this order:

1. **Stand down during a replay.** A rebase, cherry-pick or revert re-creates
   commits authored earlier while the memory worktree stays put, so syncing
   would re-pin a historical commit to today's memory. Detected via
   `--git-path rebase-merge|rebase-apply|CHERRY_PICK_HEAD|REVERT_HEAD` before
   the env unset (replay state is per-worktree), announced rather than skipped
   silently. `MERGE_HEAD` is excluded, and so is a plain `--amend` on the tip:
   both author a commit now and must pin current memory. An `--amend` at a
   rebase stop is the sharpest replay of all, and it is caught by the
   `rebase-merge` marker, not by anything about the amend. This is a contract: a
   marker added to the list must be a replay of an earlier commit, never a
   rewrite of the tip.
2. **Guard on a stale merge state** — hand the prepared merge back to the
   sub-agent while `MERGE_HEAD` is there, and when a checkout has cleared it,
   classify what survives and repair, which may mean carrying straight on
   ([merge-state-recovery.md](merge-state-recovery.md)).
3. **Sync memory** through the shared `gitlore_sync_memory_to_live`: memory's
   own stale-merge guard, the FR11 dirty/freshness gate (a store with no fresh
   approval first meets any tier's prepared-merge directive, then the summary
   request), each mounted tier's stale-merge guard, `gitlore_stage_landed_tiers`
   (adopting a tier a previous run committed inside but never recorded — the
   retry of a half-landed commit, D50), the pin guard
   (`gitlore_compose_check_pins`, aborting on an off-pin tier), down composition
   (`gitlore_compose`; rc 1 aborts on a problem in an index file with
   uncommitted changes and otherwise reports and continues, rc 2 aborts),
   `gitlore_sync_tiers_to_live` (each dirty tier: `add -A`, write its landing
   record, commit, advance its local `live`, so the gitlink the memory commit is
   about to record has already moved (D42), onto composed carrier content
   (D50)), memory's own `add -A`, removing the landing records,
   `GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>`, and removing the message file,
   then `push . HEAD:live` fast-forward-only. Divergence prepares a merge and
   yields (`gitlore_yield_merge`), exiting 1.
4. **Stage the gitlink** into the index git handed the hook — the captured
   `GIT_INDEX_FILE`, restored for that one `git add`, because a bare `add`
   misses the `-a` and pathspec index flavors and dies on `index.lock` under
   them.

Every refusal branches on `$CLAUDECODE`: agent-facing text naming the next
action, user-facing text directing them to open the project in Claude Code.

**`pre-push`** publishes in the same before-and-alongside order: each tier's
`live` to its own remote, then memory's. Failure is fatal — a tier that silently
stops publishing is indistinguishable from one with nothing to say. The
memory-absent skip stays non-blocking but warns when the gitlink about to be
published is not reachable on the memory remote, decided locally without a
fetch. Divergence routes to `/gitlore:resolve`, which diagnoses the flavor.

### The gitlink and `live`

**The gitlink a parent commit records is always an ancestor of memory's `live`,
or `live` itself.** `pre-commit` makes it `live` itself: step 4 stages the
commit step 3 just advanced `live` to. Every path that advances memory without a
parent commit — the `SessionStart` fast-forward, `commit-memory.sh`,
`/gitlore:merge`, a resolved merge — moves `live` forward and leaves the gitlink
behind as an ancestor; a `head-vs-remote` merge in particular keeps the pending
commit reachable as its second parent (D6). A gitlink behind memory's HEAD is
therefore the resting state — ` M memory` in the parent's porcelain — not drift:
it floats, the next parent commit records the move, and nothing walks memory
back to it. `SessionStart` runs `submodule update` on memory only when its
worktree is absent; the pin-to-the-gitlink discipline (D43) is for tiers inside
memory, not for memory in the parent.

The invariant is what NFR5 rests on, and it survives any number of merge rounds.
A push of `live` publishes every ancestor, so `origin/live` contains the gitlink
the moment that push succeeds, and `pre-push` orders memory before the parent,
so a parent push that goes through implies its gitlink is public. A push refused
by divergence is therefore resolved and pushed again, however many times
`origin/live` moves while a merge is under review; the parent commit — tagged or
not — is never rewritten to name the merged memory (D46).

## Decisions — D46, D50, D53, D54

Why a parent commit whose push was refused is never amended to catch up with
memory, what the commit path does about a stale carrier before it commits, and
which failures leave the approved summary standing.

**D46 — A parent commit is never rewritten to re-pin memory; a push refused by
divergence is resolved and pushed again**

The case that raised it is a release: a toolkit's `release` recipe commits a
version bump — `pre-commit` pins memory into that commit — tags it, and pushes.
`pre-push` publishes memory first, and if any store's `origin/live` moved since
the commit it prepares a merge and refuses, leaving the commit and tag local.
The window is human-paced — the FR11 approval on the release commit and the
review of the merge both sit inside it — and it reopens whenever `origin/live`
moves again while a merge waits for review, so the refusal can repeat.

The considered repair was to `commit --amend` the release commit after the merge
lands so its gitlink names the merged memory, then `tag -f`; step 1's contract
that a tip amend is authored-now would have made the hook re-pin the gitlink
itself. It is refused because the invariant above already gives correctness: the
recorded commit is the merge's second parent, it is published by the first
`live` push that succeeds, and NFR5 holds without the tag's tree ever naming the
merge. What the amend buys is coherence — a tag whose tree names the memory as
merged, and a clean parent tree immediately after — and it costs a scripted
rewrite of a tagged commit, a forced move of a tag about to be published, and an
ordering dependency on step 2's stale-merge guard, which refuses the amend until
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
index file with a problem, the approval is restamped, and the agent is told to
edit the named lines and retry, the summary needing approval again. Compose rc 1
writes nothing, so what reads as changed is the same before and after it. The
same problem in a file with no uncommitted changes — a tier dirty only outside
its carrier included — is not what this commit carries, and the manifest and
leftover-prefix rules name no index file; all of those are reported and the
commit goes ahead. The line this draws is the one D52
([tier-arrival-repair.md](tier-arrival-repair.md)) builds on: the wording of an
index a tier publishes is upstream's to change, and a structural defect that
arrives anyway — from a hand push, or an older gitlore — is the take's to
repair. Proceeding past a `gitlore_compose_check_pins` refusal instead lets this
function's own `add -A` adopt the moved gitlink and remove the condition it
refused on: the next compose projects root's older text over the carrier with
nothing left to refuse, `gitlore_sync_tiers_to_live` commits that inside the
tier, and `pre-push` ships it to the tier's own remote, so the approved upstream
fact is destroyed one commit after the warning. The pin check therefore runs
ahead of compose and aborts, naming no remedy of its own — every branch of
`gitlore_compose_check_pins` prints the one its own cause takes, and a single
abort can carry several tiers with different causes. A write failure aborts too
— a half-written carrier must not be committed.

**A failure keeps the approval, unless it prepared a merge.** What the run
writes into the store — a composed carrier, a recovered merge's up projection —
projects lines the summary already approved, yet reads newer than the commit-msg
file, and the `pre-commit` retry reuses that file as it stands. So a later
failure that prepared no merge restamps it. A merge preparation does not: it
checks merged content the summary never covered out into the worktree, and a
stale approval is the right answer after it. The stale-merge guard over the
tiers restamps on none of its failures, because it does not report which arm
failed, and some of its arms prepare nothing — a merge gitlore did not prepare,
a merge state nothing can classify, a recovery whose checkout failed. After one
of those, a retry following an earlier tier's recovered up projection reads the
approval stale (D53). The restamp is a `touch`, so it stamps the approval at
now, and freshness is `msgfile` mtime against the newest file in the store: a
write another session landed while the run was failing therefore reads as
covered by a summary that never saw it. That is an accepted residual (D54) — the
successful path holds the same window open, freshness being read once near the
top of `gitlore_sync_memory_to_live` and the commit's `add -A` running after
compose and the tier commits.

**A tier commit the run could not record is adopted on the retry.** The tier
commit moves the tier's HEAD, and only memory's later `add -A` stages the moved
gitlink. A transient `index.lock` between the two — or a tier `live` that cannot
advance, or a killed run — leaves the tier ahead of its pin, the shape the pin
check refuses, and `memory-commit-batch.sh` promises a transparent retry.
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

**D53 — The stale-merge guard's report-only arms do not restamp the approval**

`gitlore_guard_stale_merge_state` returns 1 from every failing arm and says
nothing about which one, and its arms differ in exactly the way the restamp
turns on. A continued prepared merge, and a recovery that restored a landed one,
leave content in the store the summary never covered; an orphaned `MERGE_HEAD`,
a state file nothing can classify, and a recovery whose checkout failed leave
the store as they found it. Restamping uniformly would mark the approval fresh
over merged content, so the guard restamps on none of its arms, and the price is
that a retry after a report-only arm — following an earlier tier's recovered up
projection — asks for the summary again.

The way to recover that is a per-arm return code, the guard distinguishing
"changed nothing" from "left merged content in the store" so the caller restamps
on the first. It is refused on the asymmetry of what each mistake costs. A
misclassified arm marks an approval fresh over content no summary covers, which
is the FR11 boundary breached silently, inside the one gate that exists to hold
it; what the code buys back is one visible re-approval, in a case that already
put a refusal in front of the agent. The guard would also have to keep the
classification true across every future arm, and an arm added later defaults to
whichever code its author picks rather than to the safe answer.

**D54 — A failure-time restamp that blesses a concurrent write is an accepted
residual**

`gitlore_commit_msg_freshness` reads the approval as fresh when the commit-msg
file's mtime is at least the newest file in the store, and the restamp is a bare
`touch`, which stamps it at now. A write another session landed in the store
while the run was failing is therefore older than the restamp, and the retry
commits it under a summary that never saw it.

The considered close was to snapshot the file's mtime at the top of the run and
restore it with `touch -r`, so a restamp reinstates the freshness the run began
with instead of minting new. It is refused because the success path holds the
same window open and wider: freshness is read once, near the top of
`gitlore_sync_memory_to_live`, while the `add -A` that decides what the commit
carries runs after the pin check, compose and every tier commit. A write landing
in between is committed under the approved summary with no restamp involved at
all. Closing the failure path alone would add state carried across the run for a
narrower instance of a window that stays open either way, and would read as a
guarantee the commit path does not make. What FR11 gates is a session approving
its own store; a second writer inside that store is outside what the approval
can speak for.

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

**A per-arm return code from `gitlore_guard_stale_merge_state`.** Would let the
arms that change nothing restamp the approval, saving one re-approval on a retry
that already carries a refusal. Costs a classification that must stay true
across every arm added later, and a misclassified one marks an approval fresh
over content no summary covers — the FR11 boundary breached silently by the gate
holding it (D53).

**A `touch -r` snapshot of the approval's mtime.** Would stop a failure-time
restamp blessing a write another session made mid-run, by reinstating the
freshness the run began with. The success path holds the same window open and
wider — freshness is read once, the `add -A` that decides the commit's contents
runs after compose and the tier commits — so the snapshot adds run-scoped state
for a narrower instance of a window that stays open anyway (D54).

**Leaving a tier whose adoption failed ahead of an unstaged pin.** Nothing is
staged, so the root index is not composed over, but the pin guard then refuses
every memory commit until `SessionStart` walks the tier back, and a take
meanwhile finds nothing to take, the arrival being contained in the tier's HEAD.
Walked back to the pin with the arrival kept in its local `live`, the tier is in
the shape the next take adopts (D50).
