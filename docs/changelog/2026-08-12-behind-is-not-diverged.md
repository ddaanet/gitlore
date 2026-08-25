# 2026-08-12 — A push classifies a refusal by ancestry, not by git's wording, and a failed diagnosis stops moving HEAD

`bash "$(git config gitlore.pushCommand)"` died in the `micro` repo with:

```text
Already up to date.
gitlore: could not prepare the memory merge against 'origin/live'. Inspect the memory worktree at memory/ddaanet.
```

The named worktree was clean, the skill's own routing sends a non-zero exit
without `memory merge prepared` to "surface it verbatim and stop", and nothing
in either line said what was wrong. The tier had nothing to publish at all: it
was one commit *behind* its remote.

Four sites classified a refused push on git's parenthesized reason alone. That
reason is the same for a ref that is merely behind and one that has genuinely
diverged — both are non-fast-forward pushes — and only divergence has a merge to
prepare. A behind store went to `gitlore_prepare_merge`, which checked out
`origin/live`, merged `HEAD` into it, got `Already up to date.` because HEAD was
already contained, found no `MERGE_HEAD` and returned 1.
`gitlore_merge_one_store` had the discriminator the push path lacked: two
`merge-base --is-ancestor` tests, one per direction. That is now
`gitlore_classify_refusal`, returning `behind` / `diverged` / `ahead` /
`unknown`, and all four sites route on it. The parenthesized reason still does
the job it was added for — separating an ancestry refusal from a policy,
credential or quota one — and ancestry separates the two states hiding inside
it. `behind` is reported as `/gitlore:merge`'s business and is not a failure:
the tier loop carries on to the next tier and memory's own case returns 0,
because the commit the memory pointer records is already contained in the
remote, so the lockstep that loop exists to guarantee holds. `ahead` is new and
was previously indistinguishable from divergence: the pushed ref already
contains the target, so the refusal is not about ancestry at all — the remote
moved during the push, or the fetch before it failed and the target is stale.
Preparing a merge against a stale authority would have sent out a merge missing
the very work that caused the refusal.

The second defect is what made it unrecoverable, and it is the one worth
remembering: the push publishes the **`live` branch** while the merge
preparation reasons about **HEAD**, and nothing checked that they agree. In
`micro` the tier's `live` sat 7 commits behind its own detached HEAD, so
`push origin live` was refused on a ref that was behind while the preparation
looked at a HEAD already at `origin/live` and found nothing to do. Every run
failed identically and the diagnostic pointed at neither ref. Worse, the failed
preparation left its `checkout -q --detach origin/live` in place — a diagnosis
with a side effect. HEAD then equalled `origin/live`, so the next
`/gitlore:merge` took the "already holds everything its remote does" early
return and **skipped the adopt step**, leaving the tier holding upstream's facts
while root's index still described the old ones. Recovery needed
`git checkout -q --detach live` to put HEAD back *behind* the remote so the
fast-forward-and-adopt path would run. `gitlore_check_head_live_agree` now runs
before anything is published, at both remote sites, and names both shas with the
remedy for the direction found; the local `push . HEAD:live` sites reach the
same message through the `behind` classification, since `live` already
containing HEAD *is* that drift. It reports and never repairs: which ref was
intended is not recoverable from the refs themselves, and the drift means some
earlier step left the store in a state no normal path produces.
`gitlore_prepare_merge` grew both halves of the guarantee — the ancestry test
before the detach, and a restore of the prior HEAD if it ever reaches the
no-`MERGE_HEAD` path anyway.

Making the `behind` case survivable exposed a reporting lie one layer up.
`push-memory.sh` snapshots each store's `origin/live` before the publish and
diffs it after, but `gitlore_push_stores` fetches, so a remote someone else
advanced moves that ref too — the old code would have reported
`published 1 commit(s)` for commits this run never sent. It now credits only a
tip the store's own `live` contains, and a store held back that way suppresses
the closing `every store was already up to date` rather than contradicting the
notice just printed.

Eight cases in `tests/push_behind_vs_diverged.bats`, each watched red first,
reproducing the field symptom verbatim in both flavors — including the local
one, where the old code moved HEAD by `876e008` → `ad0a878` on a diagnosis that
failed. The one existing test that changed,
`recovery: a merge that never started is reported, not announced as prepared`,
keeps its intent and its assertions on status and `MERGE_HEAD`: only the message
moved, because the state is now recognized before git can say
`Already up to date`, and it gained the HEAD-unchanged assertion that is the
point of the change. The `ahead` arm has no test — provoking a stale target ref
deterministically means breaking the fetch that precedes the push, which tests
the stub rather than the arm.
