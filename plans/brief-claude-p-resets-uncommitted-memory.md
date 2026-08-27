## Brief: `claude -p` resets an uncommitted memory store backwards, orphaning a landed merge

2026-08-26 — written from `cwd-safety`, where all three symptoms were observed.
gitlore 0.4.4.

### The bug

A nested `claude -p` session run in a repo whose gitlore memory submodule (or a
tier nested inside it) holds **committed but not yet parent-committed** work
checks that store out *backwards*, to the gitlink the parent repo still records.
The newer commit is orphaned. Nothing warns, and the reset is invisible until
someone looks at the store.

The nested session's `SessionStart` hook syncs submodules to the parent's
recorded gitlink. While the parent is uncommitted that gitlink is the *old*
commit — which is precisely the window gitlore's own approval gate holds open,
since memory is committed in the store first and lands in the parent only once
the user approves the summary. So the hazard is not exotic: it is the normal
state of a session between writing memory and committing.

Observed here: a `ddaanet` tier merge had landed as commit `2b9f64a`, the parent
was not yet committed, and a one-line `claude -p` probe run purely to verify a
`CLAUDE.md` `@` import reset the tier to `f75c3e8`. The reflog names it exactly:

```
f75c3e8 HEAD@{0}: checkout: moving from 2b9f64a... to f75c3e8...
2b9f64a HEAD@{1}: commit (merge): Merge commit 'f75c3e8...' into HEAD
```

**It leaves a split state, not a clean revert.** The tier's working `MEMORY.md`
still held the merged 101-entry index while the fact files had reverted to their
pre-merge slugs, so most index lines pointed at files that no longer existed.
That is worse than either end state, because the index is authoritative.

### Second symptom, same mechanism

`gitlore-merge-state` present with **no `MERGE_HEAD`** is this bug one step
earlier: the checkout cleared an in-progress merge and left the state file
behind. Both entry points then refuse, with no recovery path:

```
gitlore: merge state file present without MERGE_HEAD — manual intervention
required. Inspect <gitdir>/gitlore-merge-state and the memory worktree.
```

`resolve.sh` gives the same message, so `/gitlore:resolve` — the documented
repair skill — cannot repair it. This is a dead end for a user who did nothing
wrong.

**Diagnosis that settles whether anything is salvageable**, and the repair that
worked here (run from the parent repo, substituting the store path):

```sh
STORE=/Users/david/code/cwd-safety/memory/ddaanet
git -C "$STORE" rev-parse HEAD                      # equals state file's source_ref?
git -C "$STORE" status --short                      # clean?
git -C "$STORE" fsck --unreachable | grep commit    # any unreachable COMMIT?
```

HEAD still at `source_ref`, a clean worktree, and no unreachable commit together
prove nothing landed and no synthesis survives. Then move the four artifacts
aside and re-run the merge, which re-prepares cleanly:

```sh
B="$TMPDIR/gitlore-stale-merge-$(date +%s)"; mkdir -p "$B"
GD=$(git -C "$STORE" rev-parse --absolute-git-dir)
mv "$GD"/gitlore-merge-{state,mine.diff,theirs.diff,tree} "$B"/
bash "$(git config gitlore.mergeCommand)"           # should print "merge prepared"
```

Where a merge *had* landed, recovery is `git -C "$STORE" reset --hard <sha>` on
the sha the reflog names. Diff the dirty index against that commit first — here
they differed only in frontmatter, confirming nothing unique would be lost.

### Third symptom (separate bug, same session)

Index composition projects the **root** index down into a tier's carrier and can
overwrite *newer* upstream hook text with the root's stale copy. After the tier
advanced to a newer `origin/live`, composition silently reverted two tier lines
(`sandbox-effects` lost its `excludedCommands` clause, `design-doc-writing` its
doc-splitting clause). The hook's own message says "composition moves or drops
lines; it never changes a line's text", which is what made it hard to spot — the
text *was* changed. Five lines had to be hand-synced from the tier back up to
the root before composition became a no-op.

### Constraints

- The fix must not assume the parent can simply be committed first. The
  approval gate deliberately holds memory committed-in-store and
  uncommitted-in-parent; that window is the product, not a mistake.
- `claude -p` is a legitimate and currently *recommended* verification tool —
  the `ddaanet` tier's own `subagent-skips-at-import-expansion` fact tells
  agents to verify `@` imports with `claude -p` rather than a subagent,
  precisely because a subagent skips import expansion. So "don't run
  `claude -p`" is not an available answer; that advice is right about import
  expansion and silent about this hazard.

### Suggested directions (not decisions)

- Have the `SessionStart` submodule sync refuse to move a store whose HEAD is
  *ahead of* the recorded gitlink, rather than checking it out backwards. A
  fast-forward-only sync would make the bug impossible.
- Give the merge-state-without-`MERGE_HEAD` path an actual repair in
  `resolve.sh` — the diagnosis above is mechanical and needs no judgement.
- Recheck the composition direction when a tier is ahead of the root's composed
  copy; prefer the tier's text for a tier-owned line, or detect and report the
  conflict instead of silently rewriting.

### Additional context

Reproduced in `cwd-safety`, whose memory store mounts the `ddaanet` tier as a
nested store. Not filed as a memory there: the mechanism is gitlore's, so
gitlore is where it belongs.

This brief is standalone. Per the boundary convention, dropping it here is the
end of the author's involvement — nothing is being tracked from the other side,
and no reply is expected.
