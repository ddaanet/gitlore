# Merge and resolve

The divergence path end to end: the two skills that walk it, then why it has
that shape — what `live` is, which side of a merge is authoritative, how work
splits between the scripts and the agent, and the sub-agent dispatch the
directive has to authorize for itself. The conclusions open the node below; this
file is what you need while running or changing a merge.

- Trunk and direction — **D1** `live` is the memory trunk, independent of the
  parent's default branch · **D2** superseded by D41's detached model, kept for
  the record · **D41** detached at `live`: one branch model per store, one
  commit path · **D6** merge direction: the more-authoritative side is the first
  parent
- Doing the merge — **D3** ordinary checkout during resolve, not git plumbing ·
  **D7** scripts decide, the agent handles language · **D9** a sub-agent
  synthesizes the merge (requires the experimental flag) · **D13** a
  lock-contention retry wrapper guards mutating memory git calls · **D24** a
  directive that names a sub-agent carries its own authorization

---

## Mechanism

### What each phase does with `live`

- **Session start.** SessionStart detaches in place, then fast-forwards HEAD
  onto `live` when the store is clean. Uncommitted changes skip the fast-forward
  with a user-visible notice — memory is never moved out from under pending
  work. A store that arrives on a named branch (an install predating this model)
  is migrated by the same in-place detach.
- **After commit.** The commit path advances `live` immediately
  (`push . HEAD:live`, fast-forward only), so `live` holds every commit the
  moment it exists and memory is repo-global rather than branch-scoped.
  Divergence blocks and routes to `/gitlore:resolve`.
- **Two divergence gates, one shape.** A store's pending HEAD against its own
  local `live` (`pre-commit`), and its local `live` against its own
  `origin/live` (`pre-push`). Both reduce to "my pending commit vs the
  authoritative side", which is why one merge machinery serves memory and tiers
  alike (D6, D41).
- **Parent branch switches, rebases and force-pushes are independent of
  memory.** Memory history is its own concern; nothing in the parent's ref
  layout is mirrored.

### The `resolve` skill

Semantic merge of a diverged store. Self-triggering: a commit or push that fails
with `gitlore: memory merge prepared` on stderr carries everything the skill
needs, so the agent invokes it without being asked. It is also invocable as
`/gitlore:resolve` for the three entries where no directive reached an agent — a
health check after a compaction, a fresh session, or a divergence surfaced by a
`git push` the user ran in their own terminal.

The division of labour is D7's: the script decides, the agent writes prose.

1. **A gate yields.** Whichever hook meets the divergence calls
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
   runs `git add -A`, and returns a prose summary. `No conflict.` is a valid
   answer.
3. **The parent approves** the summary — from session context where it can,
   escalating to the user only when it cannot judge — and resumes the sub-agent
   via `SendMessage`. A rejection re-synthesizes.
4. **The continuation** (`resolve.sh continue-after-merge`) composes the
   indexes, runs the dangling-pointer report, commits, and pushes when the
   flavor calls for it. It finds the prepared merge by walking the stores rather
   than assuming memory, and refuses outright if two are prepared at once.
5. **The skill loops** until `resolve.sh` exits 0 (a second flavor can be
   waiting), then retries the original commit and tells the user which store was
   merged — a tier is shared with other repositories, the project store is not.

A crashed merge leaves the state file behind, and every gate guards on it. With
`MERGE_HEAD` present the store sits exactly where `gitlore_prepare_merge` leaves
one, so the directive is the ordinary `continue-after-merge` and the merge is
handed back to the sub-agent: **a prepared merge is always continued, never
discarded.** By the time a gate meets it again the sub-agent may already have
synthesized and staged an answer, and nothing in the store tells that apart from
a merge no one has touched.

The accepted trade is a merge whose authority moved while it waited — someone
pushed to `origin/live` meanwhile. It lands against the authority it was built
on, and the continuation's own fast-forward (`push . HEAD:live`, then
`push origin live` for a `head-vs-remote` merge) is then refused as a
non-fast-forward, which re-prepares the merge against the current authority and
yields again. One extra cycle, against re-synthesizing every merge that outlives
its session — and re-preparing on sight never avoided it either, since that too
merely fixed the authority as of whenever the gate happened to run.

Without `MERGE_HEAD`, the guard
classifies from the pinned pending commit and the state file's own fields, and
repairs. Two things produce that state, and they leave different remains: a
plain `git merge --abort` run in the store drops the pointers *and* resets the
index, so nothing of the merge survives but gitlore's own files, while
`git checkout` — including the no-op re-checkout `submodule update` runs — calls
`remove_branch_state()`, which unlinks `MERGE_HEAD` and `MERGE_MSG` silently
while leaving the staged result behind (a cleanly auto-merged index has no
unmerged entry for checkout to refuse over).

- **A merge landed.** A merge commit taking the pinned pending commit as a
  parent other than its first *is* that merge, wherever HEAD sits now. Searched
  across refs **and** reflogs: a landed merge HEAD was moved off is reachable
  from no ref, and `git fsck` counts the reflogs among its roots, so
  "is there an unreachable commit" is silent on exactly this case. HEAD returns
  to the merge when doing so can lose nothing — the merge already contains HEAD
  and the tree is clean — and the commands to do it by hand are printed
  otherwise.
- **A merge result is staged.** The index survives the checkout that took the
  pointers, and what it holds may be a synthesis the user has already approved,
  so `MERGE_HEAD` and `MERGE_MSG` are written back and the directive asks for
  the sub-agent again — the same continuation the `MERGE_HEAD`-present case
  gets, and for the same reason: discarding the merge would take the staged tree
  with the worktree it was written into. Refused when HEAD is not the authority
  the state file names, since that commit is what the merge was built on.
- **Neither.** The merge is dead — the `merge --abort` shape. HEAD goes back
  onto the pending commit *before* the pin is dropped, since after a preparation
  that pin is the only reference to the divergent side; every artifact a
  preparation wrote is deleted, and the gate carries on, preparing the merge
  again if the divergence is still there.

The artifacts are deleted rather than moved aside because the next preparation
recomputes each of them from the two sides. One dead end remains: a state file
that names no pending commit, with the pin gone too, leaves nothing that can say
whether the merge landed, and the message says so.

### The `merge` skill

Take what every store's remote holds, and publish nothing. A skill for the same
reasons `push` is: `/gitlore:merge` is the front door, but a session start that
named an upstream-ahead tier has to be able to reach it from context. The body
makes one call — `bash "$(git config gitlore.mergeCommand)"` — and reads the
exit the same way.

It is the only path by which a pinned tier advances (D43): per store, an
already-contained remote is nothing to do, a strictly-ahead remote is a
fast-forward followed by the tier adoption, and a diverged one prepares a merge
marked `publish: "no"`, which stops the continuation after the local `HEAD:live`
fast-forward. Stores are visited tiers-first, as on the push side, and for the
same reason memory's own missing remote is reported as nothing to take rather
than a failure: a tier with no remote is a misconfiguration worth stopping on,
since it exists to be shared, and the memory root is not. A tier fast-forward
writes the root index and commits nothing — the moved gitlink and the recomposed
index are one memory change, and recording them is the FR11 commit's job.

## Decisions — D1, D2, D3, D6, D7, D9, D13, D24, D41

**D1 — `live` branch as memory trunk, independent of parent's default branch**

Using the parent's default branch name (`main`, `master`, `develop`, …) as the
memory trunk would put every session on the branch they all merge into, and
would tie memory's ref layout to a name each project chooses for its own
reasons. `live` is a dedicated trunk no session ever works on, which makes the
merge target unambiguous in every store — memory and tiers alike.

**D2 — Per-worktree named branches by default; detached HEAD when parent is
detached**

Superseded by D41's detached-at-`live` branch model; no store carries a named
working branch. See
[changelog: branch model unified](../changelog/2026-07-20-branch-model-unified-detached-live.md)
for why.

**D3 — Ordinary checkout during resolve, not git plumbing**

`git commit-tree` + `git update-ref` were designed to avoid checking `live` out
in a linked worktree, and rejected: standard porcelain is easier to reason about
than low-level plumbing, and the merge has to leave a conflicted worktree for
the resolver to read anyway.

Under D41's detached model the prepare uses `checkout --detach <authority>`, so
there is no checkout lock and no contention to fail on: any number of worktrees
can sit on the same commit.

**D6 — Merge direction: more-authoritative side is first parent**

Across all resolve flavors, the merge commit records the more authoritative side
as first parent; the divergent side becomes the second parent. This preserves
the conventional `git log --first-parent` reading — the authoritative trunk
stays linear, divergent work appears as merged-in contributors.

- **head-vs-live** (post-commit): local `live` is the trunk; the pending commit
  on the detached HEAD is the divergent side. First parent is `live`, second is
  the pending commit.
- **head-vs-remote** (pre-push): `origin/live` is more authoritative than
  anything local. First parent is `origin/live`, second is the pending commit
  (which by then carries local `live`).

Reversing either direction would make the authoritative side look like a branch
of the divergent side, breaking the `git log --first-parent` convention.

**How the direction is achieved under the detached-at-`live` model (D41).** Both
flavors run the same two steps: pin the pending commit at
`refs/gitlore/pending`, then `checkout --detach <authority>` and merge the
pending commit in. Detaching *at the authority* is what puts it first; because
no branch is ever checked out, this cannot collide with another worktree (the
concurrent-checkout failure the old `checkout live` had). The pin exists because
nothing else references the pending commit once `merge --abort` drops
`MERGE_HEAD` — under the retired model a named branch held it.

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

SessionStart, `pre-commit`, `pre-push`, and `/gitlore:resolve` all run
`git -C <mempath> …` against the memory submodule. Concurrent Claude sessions
(or a session racing its own background work) can collide on the index/ref lock,
and a transient `index.lock` / `cannot lock ref` failure would abort the
operation — blocking a commit or stranding SessionStart under `set -e`. The fix
is `gitlore_git` (`scripts/lib/util.sh`), a drop-in wrapper that retries
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
itself: write the approval summary, write the trigger file. The merge directive
is the only one whose execution needs someone else's permission, and naming the
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

**D41 — Detached at `live`: one branch model for every store, one commit path**

Memory and every tier are checked out detached at `live`'s commit (design.md's
Architecture › Branch Model). Detached HEADs coexist on one commit, which is
what a tier needs: its gitdir is shared across a repo's memory worktrees, where
named branches would collide. The payoff is **one commit path** — a merge always
reduces to "my pending commit vs the authoritative `live`, local then remote",
and every resolution re-detaches at the new `live`.

The model is the reason D1, D2, D3 and D6 read as they do, and the reason the
tier decisions that build on it (D42, D43) can assume one shape of store rather
than two.

## Rejected alternatives

**`live` as a working branch, in any store or worktree.** `live` is the trunk
every store fast-forwards onto and no store ever checks out as a branch. Working
on it directly would make concurrent sessions compete for one ref and would
re-introduce the one-checkout-per-branch collision the detached model exists to
avoid.

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
