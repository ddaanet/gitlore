# 2026-08-03 — A memory store with no remote of its own stops withholding the tiers, in both `/gitlore:push` and `/gitlore:merge`

`/gitlore:push` refused with
`gitlore: memory submodule has no remote configured` and never reached the tier
loop, because the remote check sat above it and returned 1. Found in the `micro`
repo, where that state is deliberate: memory is local-only (`.gitmodules`
carries the `./.git/gitlore-placeholder` url, and the repo itself has no remote
either) and the tier is the only shared store. The refusal therefore withheld
exactly the half other repositories read, over a fact about the half they do not
— and the workaround was running the tier loop's own steps, `fetch origin live`
/ ff check / `push origin live`, by hand. The check now runs *after* the loop
and its failure is a stderr notice with exit 0, so a local-only memory store is
reported rather than treated as a broken install; `pre-push` inherits both, and
stops blocking the parent push for the same reason. `gitlore_merge_stores` had
the mirror of the defect with the opposite ordering: it visits the tiers first,
so it did take what upstream held, but then failed on the remote-less memory
root and reported the whole reconcile as failed. Same resolution — nothing to
take, exit 0 — and the tier branch stays a failure, because a tier exists to be
shared and one with no remote is a misconfiguration.

The placeholder url turned out to be the second half of the story. A branch
reading `./.git/gitlore-placeholder` as "no remote" went into the push path
first, on the assumption that a clone's `submodule update --init` copies it into
the submodule's `remote.origin.url`; measurement killed that. A clone on a
placeholder fails outright (`repository does not exist`) and leaves no store at
all — the placeholder never made a clone work, it only changes the error from
the one an absent url gives, which is the whole of what it buys and was recorded
as such in plan 01. The one route to the store's origin is a
`git submodule sync`, and it writes the url *absolutized* against the
superproject's location, never the registered spelling. So the two pre-existing
comparisons that motivated the branch — `resolve.sh` and `create-remote.sh`,
both testing `remote.origin.url` against the literal — could never match, and
`create-remote.sh` in particular read a synced placeholder as a real remote
already wired and refused to create one. All four sites now go through
`gitlore_is_placeholder_url`, which matches either spelling; `create-remote.sh`
also had to learn `remote set-url`, since in that state origin exists and
`remote add` fails. The string itself had three literal copies and is now
`GITLORE_PLACEHOLDER_URL` in `util.sh`, documented for what it is: a marker,
needed because git will not initialize an entry carrying no url at all. Four
cases in `tests/push_memory.bats` and `tests/pre_push_hook.bats`, each confirmed
red against the old ordering — including the one that matters, a mounted tier
reaching its remote while memory has none. `gitlore_merge_stores` has the
untouched mirror of this defect: it merges the tiers first, so it takes what
upstream holds, but then fails on the remote-less memory root, and
`/gitlore:merge` reports failure for a repo that has nothing to take.
