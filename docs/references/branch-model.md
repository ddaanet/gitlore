# Branch model — decisions D1, D6, D41

What `live` is and how a store sits on it: `live` is the memory trunk and never
a working branch (D1), every store is checked out detached at it (D41), and a
merge records the more-authoritative side as first parent (D6). Read it while
reasoning about where HEAD stands against `live` and `origin/live`, or about
which side of a divergence wins. The divergence path itself, the skills that
walk it and the decisions about how it is carried out are in
[merge-and-resolve.md](merge-and-resolve.md).

- Trunk and direction — **D1** `live` is the memory trunk, independent of the
  parent's default branch · **D41** detached at `live`: one branch model per
  store, one commit path · **D6** merge direction: the more-authoritative side
  is the first parent

---

## Mechanism

### What each phase does with `live`

- **Session start.** SessionStart detaches in place and then reports where HEAD
  stands against `live` and `origin/live`; it moves nothing (D59, with the
  report in [session.md](session.md)). A local `live` ahead of HEAD is named,
  and `/gitlore:merge` is what checks HEAD out at it. A store that arrives on a
  named branch (an install predating this model) is migrated by the same
  in-place detach.
- **After commit.** The commit path advances `live` immediately
  (`push . HEAD:live`, fast-forward only), so `live` holds every commit the
  moment it exists and memory is repo-global rather than branch-scoped. A commit
  that has forked from `live` exits 0 with a notice naming `/gitlore:merge` and
  `/gitlore:push`, whose reconcile prepares the merge.
- **Two divergences, one shape.** A store's pending HEAD against its own local
  `live` (prepared by the reconcile in `merge-memory.sh` and `push-memory.sh`),
  and its local `live` against its own `origin/live` (prepared by the take and
  the publish). Both reduce to "my pending commit vs the authoritative side",
  which is why one merge machinery serves memory and tiers alike (D6, D41).
- **Parent branch switches, rebases and force-pushes are independent of
  memory.** Memory history is its own concern; nothing in the parent's ref
  layout is mirrored.

## Decisions — D1, D6, D41

**D1 — `live` branch as memory trunk, independent of parent's default branch**

Using the parent's default branch name (`main`, `master`, `develop`, …) as the
memory trunk would put every session on the branch they all merge into, and
would tie memory's ref layout to a name each project chooses for its own
reasons. `live` is a dedicated trunk no session ever works on, which makes the
merge target unambiguous in every store — memory and tiers alike.

**D6 — Merge direction: more-authoritative side is first parent**

Across all resolve flavors, the merge commit records the more authoritative side
as first parent; the divergent side becomes the second parent. This preserves
the conventional `git log --first-parent` reading — the authoritative trunk
stays linear, divergent work appears as merged-in contributors.

- **head-vs-live** (reconcile): local `live` is the trunk; the pending commit on
  the detached HEAD is the divergent side. First parent is `live`, second is the
  pending commit.
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

**D41 — Detached at `live`: one branch model for every store, one commit path**

Memory and every tier are checked out detached at `live`'s commit (design.md's
Architecture › Branch Model). Detached HEADs coexist on one commit, which is
what the memory store needs: its worktrees share one gitdir, and git refuses to
check the same named branch out in two of them. A tier gets the opposite
treatment — each memory worktree materializes its own tier clone, with its own
refs (git 2.47.3; the tier fixtures' characterization notes record the same) —
so a named branch there would not collide but diverge per worktree, with nothing
watching either copy. Neither store carries one. The payoff is
**one commit path** — a merge always reduces to "my pending commit vs the
authoritative `live`, local then remote", and every resolution re-detaches at
the new `live`.

The model is the reason D1 and D6 above and D3 in
[merge-and-resolve.md](merge-and-resolve.md) read as they do, and the reason the
tier decisions that build on it (D42, D43) can assume one shape of store rather
than two.

## Rejected alternatives

**`live` as a working branch, in any store or worktree.** `live` is the trunk
every store fast-forwards onto and no store ever checks out as a branch. Working
on it directly would make concurrent sessions compete for one ref and would
re-introduce the one-checkout-per-branch collision the detached model exists to
avoid.
