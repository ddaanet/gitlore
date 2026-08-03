## Brief: a session start between `/gitlore:merge` and the memory commit eats the merge

Observed 2026-08-03, live, in this repo — twice in one session.

### What happens

`/gitlore:merge` lands a tier merge, fast-forwards the tier's local `live` onto
the merge commit, and leaves the moved gitlink **unstaged** in the memory store,
to ride the next memory commit. `scripts/cc-hooks/session-start.sh:228` then
pins every active tier unconditionally:

```sh
gitlore_git -C "$mempath" submodule update --init -- "$tier"
```

`submodule update` checks the tier out at the gitlink **the index holds**, which
is still the pre-merge commit. HEAD moves backwards, and the tier's fact files
revert to their pre-merge content. The reflog is the whole story:

```
e0f57ac HEAD@{0}: checkout: moving from 8c21399 to e0f57ac
8c21399 HEAD@{1}: commit (merge): Merge commit 'e0f57ac...' into HEAD
```

Nothing reports it. `/gitlore:merge` had already exited 0, and the next session
says the tier is clean. What survived was the tier's `live` branch — the merge
commit is reachable, but only if you know to look.

The unfinished-merge guard at `session-start.sh:210` does not cover this: the
merge is *finished*, the state file is cleared and there is no `MERGE_HEAD`. The
window is specifically "landed, not yet recorded in the memory store".

Worse than a plain revert: the root index had already been recomposed with
upstream's lines and that edit is a memory-store working-tree change, which
survives. The store is then internally inconsistent — index lines describing
augmented facts whose files no longer carry the augmentation.

`/gitlore:push` shares the continuation, so it has the same window.

### Fix to evaluate

Stage the moved tier gitlink in `continue-after-merge`, alongside the composed
index it already writes — `git -C "$mempath" add -- "$tier"`. `submodule update`
reads the index, so a staged gitlink makes the pin idempotent instead of
destructive, and the design's own words for the post-merge state ("the moved
gitlink and the recomposed root index ride the next memory commit") stay true.

Rejected on sight: skipping the pin when the tier is *ahead* of its gitlink.
`session-start.sh:224-227` pins unconditionally on purpose — every clone made
before tiers were pinned sits ahead already, and that is the case the
unconditional pin exists to correct.

Needs a bats test over the real sequence: land a tier merge, run the SessionStart
tier pass, assert the tier HEAD still contains the merge. Assert the negative
against the *commit*, not a string — a test that only checks `git status` is
clean passes in both worlds.

### Recovery, if it has already happened

```sh
cd <repo>/memory/<tier>
git checkout -- MEMORY.md          # discard the stale re-composed index
git checkout -q --detach live      # `live` still holds the merge commit
```

Then re-run the reconcile and commit the parent, which records the gitlink.
