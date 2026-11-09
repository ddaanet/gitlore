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
- The commit path — **D50** the commit writes no index and aborts when a compose
  pass would change one; a tier off its pin is fatal (one ahead of it naming the
  take), and so is a compose problem in an index file the commit changes, while
  every other compose refusal is reported

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
`submodule update` on a module only when its worktree is absent; the gitlink
record of D43 is for tiers inside memory, not for memory in the parent.

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

**D50 — The commit path writes no index and aborts on a pending compose; a tier
off its pin, or a compose problem in an index file the commit changes, is
fatal**

The commit path publishes what the session composed; it never composes. Anything
`PostToolBatch` did not compose is assumed to be an exterior change — a human in
an editor, a dead hook, a manifest edit in a terminal — and failing on it beats
silently fixing it: a repair at the commit would publish a tier carrier no
summary described and no session saw. `gitlore-commit` and
`gitlore_sync_memory_to_live` therefore run `gitlore_compose_pending`, which
computes what `gitlore_compose` would write through the same
`gitlore_compose_pass`, each index rendered by the same `gitlore_compose_render`
and only the last step differing: the write replaces the file, the check reports
its path. It writes no index and no file in a store and moves no tier; a tier
ahead of its pin fails the pin guard ahead of it, naming the take, so the
`add -A` records no tier the root index has not taken. A non-empty result aborts
the commit before any store is committed, naming every index the pass would
change and the remedy: `gitlore-compose` for an agent, the script's path for a
terminal user. `gitlore-compose` (`scripts/compose-memory.sh`) runs the full
pass with the write, repeating it until a pass changes nothing; on a composed
store it writes nothing. The orphan report runs after the check, since a line a
tier added changes nothing in a pass; it is reported and never refuses.

The check precedes the section check in `gitlore-commit`, so a summary is judged
against the state the remedy leaves. It follows the prepared-merge guards, so a
tier holding a prepared merge is answered by the merge's directive. The sync
runs it ahead of `gitlore_sync_tiers_to_live`, so no gitlink is staged against a
carrier a later compose would rewrite.

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
— is the take's to repair. A check that cannot read an index aborts too.

**The pin guard covers every mounted tier, dormant ones included, and refuses a
tier off its pin.** `gitlore_compose_check_pins` reads the pin from the memory
store's *index*, since a gitlink staged for the next memory commit is what that
commit records, and aborts before the pending check when a tier's `HEAD` is not
its pin. The guard loops over mounted tiers, not the manifest, because the
commit's `add -A` records a dormant tier's `HEAD` too, and a raw pull in memory
that leaves a tier checkout behind the pin would otherwise record the older
commit silently and move the pin backward. Each cause prints its own remedy, so
a single abort can carry several tiers:

- **mid-merge** — `/gitlore:resolve` lands the merge; the return-to-the-pin
  checkout would unlink `MERGE_HEAD` and destroy it;
- **the pin is no object in the tier** — a commit this checkout has not fetched,
  the shape a raw pull in memory leaves: `/gitlore:merge` fetches the tier and
  fast-forwards it, and a commit no repository holds is the integrity error of
  [unresolvable-pin.md](unresolvable-pin.md);
- **ahead of the pin** — the root index has not taken its lines:
  `/gitlore:merge` composes them into the root index and records the tier (D78,
  in [take-and-compose.md](take-and-compose.md));
- **behind the pin** — `/gitlore:merge` fast-forwards it;
- **beside the pin**, each holding commits the other lacks — a checkout of the
  pin, then `/gitlore:merge`, so projecting the root index onto the tier cannot
  overwrite what it holds.

`SessionStart` reports the same state.

**A tier ahead of its pin is refused, naming the take.** No completed operation
leaves a tier's `HEAD` ahead of the gitlink the index records: the take records
the tier it moves, the memory merge's continuation and the recovery stage what
they compose, and the commit records every tier after the guard saw them on
their pins. What produces the state is the one transient — a tier merge's
continuation lands the merge in the tier and composes nothing, so the tier sits
ahead until the `/gitlore:merge` rerun — or a run killed between a tier's move
and its record, a take or a commit, or hand git inside the tier; recording it
silently would publish the tier's commits with their lines never composed into
the root index. The take is the one path that composes before it records (D78),
so the refusal names `/gitlore:merge`; nothing puts the tier back on its pin,
since the take needs it where it stands. A commit interrupted between a tier's
commit and memory's `add -A` leaves that shape too, and the retry refuses it the
same way.

## Rejected alternatives

**Amending a tagged parent commit to re-pin memory after a `pre-push` merge.**
Buys only that the tag's tree names the merged memory; the recorded commit is
already an ancestor of `live` and public on the first successful push. Costs
`tag -f` on an unpublished tag, a rewrite of a tagged commit, and a sequencing
dependency on the stale-merge guard (D46).

**Composing at the commit.** A carrier or root index left stale by an edit no
batch composed would be repaired at once, but the repair ships content no
approved summary covers and hides an exterior change from the session that made
it. The commit fails on it instead and names `gitlore-compose` (D50).

**Committing through a tier ahead of its pin.** The `add -A` would record a tier
whose lines the root index has not taken, with no approved summary of its own,
and hide the killed take or hand git that moved it; the three-way the take runs
is what carries its lines into root before the gitlink is recorded (D78), and
the refusal costs one `/gitlore:merge` (D50).
