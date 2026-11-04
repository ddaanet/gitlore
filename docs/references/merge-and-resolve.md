# Merge and resolve

The divergence path end to end: the two skills that walk it, then why it has
that shape — how work splits between the scripts and the agent, and the
sub-agent dispatch the directive has to authorize for itself. What `live` is,
which side of a merge is authoritative and the detached-at-`live` branch model
are in [branch-model.md](branch-model.md). The conclusions open the node below;
this file is what you need while running or changing a merge.

- Doing the merge — **D3** ordinary checkout during resolve, not git plumbing ·
  **D7** scripts decide, the agent handles language · **D9** a sub-agent
  synthesizes the merge (requires the experimental flag) · **D13** a
  lock-contention retry wrapper guards mutating memory git calls · **D24** a
  directive that names a sub-agent carries its own authorization · **D49** merge
  commits are canned and unprompted, and an explicit take commits its own
  bookkeeping

---

## Mechanism

### The `resolve` skill

Semantic merge of a diverged store. Self-triggering: a merge or push that fails
with `gitlore: memory merge prepared` on stderr carries everything the skill
needs, so the agent invokes it without being asked. It is also invocable as
`/gitlore:resolve` for the three entries where no directive reached an agent — a
health check after a compaction, a fresh session, or a divergence surfaced by a
`git push` the user ran in their own terminal.

The division of labour is D7's: the script decides, the agent writes prose.

1. **A divergence yields.** Whichever script meets it calls
   `gitlore_yield_merge`, which prepares the merge, writes a state file into the
   diverged store's gitdir, and emits the directive on stderr. Preparation pins
   the pending commit at `refs/gitlore/pending`, checks the authority out
   detached (so it becomes the merge's first parent, D6), merges the pending
   commit in with `merge.conflictStyle=diff3`, and re-merges every index file
   entry-wise (D44). One shape covers both flavors: `head-vs-live` (pending
   commit against local `live`) and `head-vs-remote` (against `origin/live`). A
   gate reaches that call only for a *genuine* divergence: git refuses a merely
   **behind** ref with the same `(fetch first)` / `(non-fast-forward)` it gives
   a diverged one, so the parenthesized reason separates an ancestry refusal
   from a policy or credential one, and `gitlore_classify_refusal` separates the
   two ancestries inside it — `behind` (nothing of ours to publish), `diverged`
   (the only case with a merge to make), and `ahead` (the pushed ref already
   contains the target). Preparation refuses outright when the authority already
   contains the pending commit, and restores the prior HEAD if it reaches the
   no-`MERGE_HEAD` path: HEAD left detached on the authority makes the next
   `/gitlore:merge` take its already-contained early return and skip the tier
   adoption, stranding a store that holds upstream's facts under an index
   describing the old ones.
2. **The skill parses the directive** — the store path, the state file, and a
   verbatim continuation command — and dispatches the `gitlore:memory-merger`
   sub-agent, which the directive's own text authorizes rather than offers
   (D24). The sub-agent gets fresh context (D9), the two side diffs and the file
   tree (D44), synthesizes holistically whether or not git flagged a conflict,
   stages by explicit path in the store the state file names, and returns a
   prose summary. `No conflict.` is a valid answer.
3. **The parent reviews** the summary against the two side diffs and resumes the
   sub-agent via `SendMessage`. A rejection re-synthesizes. The user is never
   prompted: both sides of the merge already passed an approval gate, so the
   resolution is automated from their perspective (D49).
4. **The continuation** (`resolve.sh continue-after-merge`) composes the indexes
   — refusing to commit, and keeping the merge prepared, while a file the merge
   changed still holds conflict markers or the merged index itself fails the
   check, so the parent rejects with the problem lines and the sub-agent
   re-synthesizes (D52) — runs the dangling-pointer report, commits under the
   canned merge message (D49), commits a tier merge's bookkeeping in the root
   store, and pushes when the flavor calls for it; a push refused for any reason
   but divergence exits 1 once an unadopted tier is rested
   ([tier-stores.md](tier-stores.md)). It finds the prepared merge by walking
   the stores rather than assuming memory, and refuses outright if two are
   prepared at once. Only its exit 0 means the merge landed: every exit before
   the merge commit is non-zero. A message file that cannot be created, a
   message that cannot be built and a refused merge commit each print
   `… so the merge was not committed; the merge stays prepared.` after the
   failing command's own text, and a rerun once that cause is fixed lands the
   merge. The sub-agent and the skill route those lines, the merged-index and
   conflict-marker refusals, a fresh `gitlore: memory merge prepared` and a
   post-landing `gitlore: pushing '…' failed, and not because of divergence` by
   name, and report any other non-zero outcome as unrecognised rather than
   landed. The last two both follow a landed merge: the fresh directive goes
   back through the loop, while the push failure ends in the summary, with any
   rest remedy it printed still to run.
5. **The skill loops** until `resolve.sh` exits 0 (a second flavor can be
   waiting; the script gates every tier before memory, the order publishing
   keeps, so memory's pointer never goes out ahead of a tier it records), then
   retries the original commit and tells the user which store was merged — a
   tier is shared with other repositories, the project store is not. A rest
   remedy the continuation printed is relayed as still to run: the loop can
   reach a healthy exit before it has run.

**Memory's `live` reaches its remote only from memory's own gate, which runs
last.** `check_store_gates` ends by pushing `live` to `origin`, and
`scripts/resolve.sh` calls it for every mounted tier before calling it for the
memory root, so a tier gate that refuses stops the run with memory unpublished:
the memory remote never holds a gitlink a tier's remote cannot resolve, which is
what D17 orders the gates to prevent. A memory remote that has never held `live`
is no exception. The run learns that from the `ls-remote` its reachability probe
already pays for, and spends it only on skipping the `fetch origin live` that
would otherwise print git's `couldn't find remote ref live`; the publication
itself still waits for the gate.

A crashed merge leaves a state file behind, and every gate guards on it —
classifying what survives and repairing, which may mean carrying straight on.
The state machine (marker vs full state file, `MERGE_HEAD` present, cleared by a
checkout, landed, staged, dead) is in
[merge-state-recovery.md](merge-state-recovery.md).

### The `merge` skill

Take what every store's remote holds, and publish nothing. A skill for the same
reasons `push` is: `/gitlore:merge` is the front door, but a session start that
reported commits on `live` not checked out here, upstream memory commits or an
upstream-ahead tier has to be able to reach it from context. The body makes one
call — `gitlore-merge` — and reads the exit the same way.

For the memory root only, the take opens with the local half: a `live` that
strictly contains HEAD — commits another checkout of the store made — is checked
out detached when the store is clean, and the run says HEAD was fast-forwarded
onto its local `live`. A dirty store is reported and left where it is (exit 0),
and the remote comparison below then withholds its "already holds everything"
line, which would claim finished a store that is not; commit memory and run
`/gitlore:merge` again. A tier's local `live` ahead of its pin is adopted by the
tier loop instead (D43).

Per store, an already-contained remote is nothing to do, a strictly-ahead remote
is a fast-forward followed by the tier adoption, and a diverged one prepares a
merge marked `publish: "no"`, which stops the continuation after the local
`HEAD:live` fast-forward. Memory's own missing remote is reported as nothing to
take rather than a failure: a tier with no remote is a misconfiguration worth
stopping on, since it exists to be shared, and the memory root is not. A tier
fast-forward writes the root index and commits the pair — the moved gitlink and
the recomposed index — under the canned bookkeeping message, so an explicit take
leaves the store clean (D49).

Stores are visited **root-first**, the mirror of the publish order. A root
commit arriving from upstream already records the tier commits it names, all of
them on the tier's own remote, so taking it first leaves each tier merely
behind, and the tier loop's own fast-forward catches the worktree up with
nothing left to record; tiers-first inverts that — the tier take's bookkeeping
commit meets the upstream root's equivalent commit as a divergence and spends a
synthesis on two sides that recorded the same fast-forward. Publishing keeps the
opposite order for the opposite reason: a pointer must never go out ahead of
what it points at.

## Decisions — D3, D7, D9, D13, D24, D49

**D3 — Ordinary checkout during resolve, not git plumbing**

`git commit-tree` + `git update-ref` were designed to avoid checking `live` out
in a linked worktree, and rejected: standard porcelain is easier to reason about
than low-level plumbing, and the merge has to leave a conflicted worktree for
the resolver to read anyway.

Under D41's detached model ([branch-model.md](branch-model.md)) the prepare uses
`checkout --detach <authority>`, so there is no checkout lock and no contention
to fail on: any number of worktrees can sit on the same commit.

**D7 — Scripts decide, agent handles language**

Detection and branching logic (hook-manager type, remote provider, merge state,
divergence flavor) lives in shell scripts that output structured results. The
agent handles language-level work: summarizing memory changes, synthesizing
merged memory content, communicating with the user, and answering clarification
questions for sub-agents.

Benefits:

- **Deterministic and testable:** scripts can be unit-tested; model behavior
  can't.
- **Auditable:** git plumbing is visible in code, not hidden behind
  natural-language reasoning.
- **Stable across model versions:** logic that must not drift doesn't rely on
  the model.

Load-bearing for `/gitlore:resolve`: the script determines divergence flavor,
selects plumbing sequences, and dispatches the sub-agent with a scoped context.
The agent never decides which git commands to run.

**D9 — Sub-agent for merge synthesis (requires experimental flag)**

`/gitlore:resolve` dispatches a sub-agent with fresh context for merge
synthesis. The parent session's in-memory context reflects the pre-merge state
of files; after `git merge --no-commit --no-ff` rewrites them on disk, the
parent's assumptions are stale. A sub-agent reads the post-merge state freshly,
avoiding stale-context writes.

The sub-agent + SendMessage pattern requires
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Install checks for the flag and offers
to enable it. Known limitations (no session-resumption for in-process teammates,
task-status lag) are documented; they do not affect the gitlore use case, which
runs the sub-agent within a single live session.

When the flag stabilizes or the feature becomes default, the install-time check
becomes a no-op. No other design changes needed.

**D13 — Lock-contention retry wrapper for mutating memory git calls**

SessionStart, `commit-memory.sh`, `pre-push`, and `/gitlore:resolve` all run
`git -C <mempath> …` against the memory submodule. Concurrent Claude sessions
(or a session racing its own background work) can collide on the index/ref lock,
and a transient `index.lock` / `cannot lock ref` failure would abort the
operation — blocking a commit or push, or stranding SessionStart under `set -e`.
The fix is `gitlore_git` (`scripts/lib/util.sh`), a drop-in wrapper that retries
`git "$@"` on transient lock contention with exponential backoff. The default
schedule (`0.1 0.2 0.4 0.8 1.6 3.2 3.7`) sums to exactly 10.0s wall-clock — the
last term is the budget remainder, not a doubled value — and is overridable via
`GITLORE_GIT_RETRY_SCHEDULE` (tests set it to zeros for instant runs).

Only lock-contention failures retry, recognized by `gitlore_git_is_lock_error`
matching `index.lock`, `file exists`, `unable to create …*.lock`,
`cannot lock ref`, and `another git process`. Every other failure fails fast —
retrying a real error wastes the budget. The final attempt's stderr and exit
code surface unchanged and stdout passes through untouched, so the wrapper is
transparent to callers. Applied to mutating calls only (`branch`, `checkout`,
`merge`); read-only probes never take the lock and stay on plain `git`.

**D24 — A directive that names a sub-agent carries its own authorization**

The reader of a gate's stderr is the agent, and above every surface a repo
controls sits a harness rule —
*do not call the AgentTool unless the user requested it* — with no scope and no
rationale, which nothing in a `CLAUDE.md`, a skill or a memory file can qualify.
Every other blocking gitlore directive asks for an act the agent performs
itself: draft the approval summary, run the commit. The merge directive is the
only one whose execution needs someone else's permission, and naming the
sub-agent does not grant it — read literally,
*dispatch the memory-merger sub-agent with state file:* describes an option, so
an agent meeting it reports the blocker and stops mid-push.

The directive therefore states the licence instead of assuming it: **the git
operation that triggered the merge is itself the request for the dispatch.**
That satisfies the harness rule as written, so no exception, override or
per-machine configuration is needed. Keeping the argument in the text is what
scopes it — the authorization is visibly *this* dispatch's, derived from *this*
operation, never a general licence to skip a permission gate. The directive also
separates the two approvals it carries: the dispatch needs none, the merge the
sub-agent proposes still does, and the continuation line says so. The name is
emitted plugin-qualified (`gitlore:memory-merger`) because a bare one fails
discovery. `gitlore_emit_merge_directive` is the single emitter, so the shape
reaches every yield that asks for the sub-agent — a fresh preparation, a stale
state file with its `MERGE_HEAD` intact, a staged merge whose pointers were
restored — and any directive added later that names a sub-agent.

**Rejected: putting the qualification anywhere but the directive.** Amending the
harness rule in the consumer's own configuration ("…unless a hook directive
instructs it") edits something that is not user configuration, and repeats per
machine. Recording it as a memory fact makes every consumer learn separately
what one directive could say once, and a reader whose store lacks the fact meets
the same wall. Leaving the agent to infer authorization from context is exactly
the inference the blanket rule exists to remove.

**D49 — Merge commits are canned and unprompted; an explicit take commits its
own bookkeeping**

Both parents of every gitlore merge already passed an approval gate: the local
side at its own FR11 commit, the upstream side in the repo that published it. A
merge introduces no unapproved content, so prompting the user gates a decision
already made — a merge is automated from their perspective, and merge and
bookkeeping commits are FR11's stated exemption. So is the commit a take makes
to repair an arriving index the root cannot adopt, which restructures lines
upstream already approved and adds no text (D52, in
[tier-arrival-repair.md](tier-arrival-repair.md)). The parent agent still
reviews the sub-agent's synthesis before the continuation runs; that check is
the reviewer's, not the user's.

The messages are canned, shaped for each commit's readers. A **merge commit**,
in whichever store diverged, is `merge <merged-repo> from <consumer>` — repo
from the store's remote url, consumer from the parent working tree, because a
shared tier's history is read by every repo that mounts it and the subject
should say which one landed the merge. Its body lists the subjects of the
**second-parent (local) side**: what the merge brought *into* `live`. The local
repo is the only consumer that cares what was new in `live`; everyone else
already holds the first-parent side, and what the merge contributed is the news
— git's own `--log` convention under D6's direction. A
**tier take's bookkeeping commit**, in the memory root, is
`Update MEMORY.md for <tier> tier merge.` with the taken tier subjects as its
body, so a fast-forward take — which creates no tier commit — is still recorded.

The line between committing and not is **intention**. An explicit operation —
`/gitlore:merge`, `/gitlore:push`, a resolve continuation servicing an explicit
commit or push — leaves a clean store, committing the pair and advancing `live`;
SessionStart takes nothing and commits nothing (D59). One guard survives: a root
store that held unapproved work before the take keeps the staged-pair discipline
(D43), because a canned `commit` may only ever carry what the take itself
staged. And push takes upstream under the same decision — attempt → take →
attempt again — so only a genuine divergence yields to `/gitlore:resolve`, and
the report credits only tips the store held before the run: a take is not a
publication.

## Rejected alternatives

**`git commit-tree` + `git update-ref` for the resolve merge.** Low-level
plumbing to avoid checking a branch out. Unnecessary — the merge prepares with
`checkout --detach <authority>`, which is ordinary porcelain, easier to reason
about, and cannot collide with another worktree because nothing is ever checked
out as a branch (D3, D41).

**A temporary worktree for resolve.** Indirection with no payoff; the store's
own worktree is where the merge belongs.

**`claude --print` for conflict resolution.** No session context, no way to ask
the user, no memory of what produced the changes.

**Single-agent resolve with a post-hoc context refresh.** The parent's in-memory
picture of the files is pre-merge and stale the moment git rewrites them on
disk. A sub-agent reads the post-merge state fresh (D9).
