# 2026-09-01 — A tier `live` ahead of its pin is adopted, not checked out

`/gitlore:push` in a repo running 0.6.0 refused up front on its `ddaanet`
tier:

```text
gitlore: tier 'ddaanet''s HEAD is not at its local 'live' (HEAD ea39932, live 2800e0e),
so nothing was published. Put HEAD back on 'live':
git -C ".../memory/ddaanet" checkout --detach live
```

Following that instruction verbatim published nothing and took the tier off
the commit the memory store records for it, so the next edit to the root index
was refused by composition, which named the opposite move. Two gates asserted
different invariants about one ref, and obeying the first produced the state
the second rejects.

Neither gate was wrong about its own store. `live` is what a push sends and
what the parent's gitlink lags behind, so for the memory root — which has no
pin above it, and which SessionStart checks out at `live` — putting `HEAD`
back on `live` is the session's own act and the right remedy. A tier is pinned
at the gitlink the memory store's index records (D43), because the down
projection is safe only while root's block and the carrier agree by
construction. `gitlore_check_head_live_agree` was one store-kind-blind gate
stating only the root's answer.

`live` ahead of a `HEAD` at the pin holds tier commits the memory store never
recorded. A tier commit advances both refs together, so they part only when
the memory side loses the moved gitlink afterwards — a merge preparation
checks the memory store out and rewrites its index — and the next SessionStart
pins `HEAD` back while `live` keeps what was approved. Nothing reports it:
`live` is invisible to the take's ancestry test and to SessionStart's, both of
which read `HEAD`.

So the state is an unadopted take, and neither ref may be moved onto the
other: rewinding `live` discards approved commits, and moving `HEAD` alone
strands the store. `gitlore_adopt_advanced_live` performs the
fast-forward-plus-adoption a remote arrival already gets — working tree onto
`live`, carrier projected up into root's block, pair staged and recorded in
the canned bookkeeping commit — sourced from the local ref, so no ref moves at
all. `gitlore_adopt_tier_into_root`, extracted from the remote take, is the
tail both share.

It runs at the head of every take, before any ancestry is read: every test
there reads `HEAD`, and adopting first means the classification against the
remote sees everything the store already holds rather than presenting local
commits as a fast-forward the ff-checked `push .` then refuses. The publish
preflight calls the whole take pass rather than adopting the one tier, for the
reason its behind-tier branch already gives — the pass runs root-first, and a
tier's bookkeeping commit would otherwise meet an equally-behind root's
upstream one as a divergence. There is no `continue` after it: what was
adopted has never been published, so that tier's push is exactly what happens
next.

Routing to `/gitlore:merge` without teaching the take this source would have
been a loop. `gitlore_merge_one_store` classifies by `origin/live` against
`HEAD`; with the remote contained in `HEAD` it answered `already holds
everything its remote does` and returned 0, while the push was refused again.
The field session escaped only because its remote happened to be ahead of
both refs.

The gate now branches on store kind and keeps the checkout for the root alone;
a tier is sent to the take and told not to check out at `live`. The
`live`-behind arm and the diverged arm are unchanged. Its message also drops
the possessive that rendered `tier 'ddaanet''s` — a label already carrying
quotes takes an em dash, matching the reporting elsewhere in the file.

The memory root is deliberately not adopted here. Its `live` ahead of `HEAD`
is answered by a checkout that is correct, cheap and what the next session
performs regardless, and moving the root store would take a decision the refs
do not carry.

`docs/design.md`'s branch-model rationale is corrected alongside: it hung
git's one-branch-per-worktree rule on tiers, "whose gitdir is shared across
all of a repo's memory worktrees." Measured on git 2.47.3, tiers are the one
store where that is false — each memory worktree materializes its own tier
clone, with its own `live`, which the tier fixtures' own characterization
notes already record. The rule binds on the memory store, whose worktrees do
share a gitdir; for a tier the argument for detaching is that a named branch
there would not collide but diverge per worktree, unwatched.

Cases in `tests/merge_memory.bats` and `tests/push_behind_vs_diverged.bats`,
each watched red first: the take that adopts and leaves the pin, the root
index and the checkout naming one commit; the push that adopts and publishes
instead of naming a checkout; and the gate's tier arm, reached directly, since
the preflight now adopts before it can fire.
