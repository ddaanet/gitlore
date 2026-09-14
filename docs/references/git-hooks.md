# Git hooks — decisions D46, D50

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
- The commit path — **D50** the store is composed before it is committed, a
  compose refusal reported and a pin refusal fatal

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
   own stale-merge guard, the FR11 dirty/freshness gate, each mounted tier's
   stale-merge guard, `gitlore_stage_landed_tiers` (adopting a tier a previous
   run committed inside but never recorded — the retry of a half-landed commit,
   D50), the pin guard (`gitlore_compose_check_pins`, aborting on an off-pin
   tier), down composition (`gitlore_compose`; rc 1 reports and continues, rc 2
   aborts), `gitlore_sync_tiers_to_live` (each dirty tier: `add -A`, write its
   landing record, commit, advance its local `live`, so the gitlink the memory
   commit is about to record has already moved (D42), onto composed carrier
   content (D50)), memory's own `add -A`, removing the landing records,
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
or `live` itself.** `pre-commit` makes it `live` itself: step 5 stages the
commit step 4 just advanced `live` to. Every path that advances memory without a
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

## Decisions — D46, D50

Why a parent commit whose push was refused is never amended to catch up with
memory, and what the commit path does about a stale carrier before it commits.

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

**D50 — The commit path composes before it commits; a pin refusal is fatal**

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
adopting one destroys.** A `gitlore_compose_check` refusal withholds a
projection and destroys nothing, so the commit proceeds with the carrier as it
stands and the refusal is only reported. Proceeding past a
`gitlore_compose_check_pins` refusal instead lets this function's own `add -A`
adopt the moved gitlink and remove the condition it refused on: the next compose
projects root's older text over the carrier with nothing left to refuse,
`gitlore_sync_tiers_to_live` commits that inside the tier, and `pre-push` ships
it to the tier's own remote, so the approved upstream fact is destroyed one
commit after the warning. The pin check therefore runs ahead of compose and
aborts, naming no remedy of its own — every branch of
`gitlore_compose_check_pins` prints the one its own cause takes, and a single
abort can carry several tiers with different causes. A write failure aborts too
— a half-written carrier must not be committed.

**A failure keeps the approval, unless it prepared a merge.** What the run
writes into the store — a composed carrier, a recovered merge's up projection —
projects lines the summary already approved, yet reads newer than the commit-msg
file, and the `pre-commit` retry reuses that file as it stands. So every later
failure restamps it. A merge preparation does not: it checks merged content the
summary never covered out into the worktree, and a stale approval is the right
answer after it.

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
([merge-state-recovery.md](merge-state-recovery.md)). A take and a landed merge
continuation that stage nothing also return the tier to its pin, keeping what
arrived in its local `live` for the next take to adopt
([tier-stores.md](tier-stores.md)). The one exception is a tier commit the
commit path itself made, whose carrier root already describes, so there is
nothing to project up.

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
