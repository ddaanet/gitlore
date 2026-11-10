# The unresolvable pin — decision D79

A commit that a pin records and the repository that should hold it lacks: what
nothing does over it, what is reported, and the remedy each level has. Read it
when a `SessionStart` or `/gitlore:resolve` report names a commit that no
repository holds, or when changing a take, a compose or the revert. The take and
compose it stops are in [take-and-compose.md](take-and-compose.md); the position
report beside it is in
[publishing-divergence.md](publishing-divergence.md).

- The pin — **D79** an unresolvable pin is an integrity error at every level:
  nothing composes over it and nothing is recorded under it; a tier gitlink is
  published by the checkout that recorded it or reverted by `/gitlore:resolve`,
  and the parent's pin on memory has no command

---

## Mechanism

### What counts

Two pins can name a commit the module lacks: memory's gitlink on a tier, and the
parent's pin on memory. A pin is unresolvable only when the module's checkout
lacks the commit *and* one fetch of the module's `live` did not bring it, so a
commit only the remote holds is a take's business, not an integrity error.
`SessionStart` makes that fetch read-only while it reports; `/gitlore:resolve`
fetches before it decides (`gitlore_resolve_check_pins`). A failed fetch cannot
tell an unfetched commit from a lost one, so `SessionStart` reports nothing for
it. `/gitlore:resolve` reports a failed tier fetch as such, with no revert
command, and exits 1; `revert-pin` refuses over it. Both fetch `origin live`
only, so a commit held only on another remote branch reads as unresolvable.

The tier pin is read from memory's *index*, as the pin guard reads it: a staged
gitlink is what the next memory commit records.

### What it stops

A recorded commit the module lacks is never a base. The compose refuses a tier
whose base commit the tier does not hold, and composes nothing over it. A take
refuses a root merge or fast-forward onto a commit recording such a gitlink,
after taking the tiers, with memory neither moved nor composed; the message
names the commit, the tier and the remote that lacks it. No compose reads a
fallback base. The pending report and the dangling report hold back for the lost
tier: the dangling lines under it are not stale, since their files are in the
lost commit, and telling anyone to delete them would be wrong. No commit records
a module below such a pin at another commit, so the pin never moves backward
silently.

### The report

`SessionStart` and `/gitlore:resolve` name the commit and the remote that lacks
it, plus the repo `.gitmodules` names when that is a different repo from the
module's remote. "A different repo" is not a string comparison: by D64
`.gitmodules` records https for a GitHub repo while the module's own remote can
stay on ssh, so the two urls are compared in https form with userinfo dropped
(D80). `/gitlore:resolve` does not say "healthy" over it; it checks before the
gates, so no push publishes past it, and exits 1.

The urls are text the user's config or a contributor's PR chose. The user's line
shows them under D80; the agent's line says the user has them.

The remedy is per level.

- **A tier gitlink.** The checkout that recorded it runs `/gitlore:push`, which
  publishes the tier commit; the next `/gitlore:merge` then retries. When that
  checkout no longer exists and this checkout's memory index records the pin,
  `/gitlore:resolve` prints the revert command, `resolve.sh revert-pin <tier>`.
  A pin recorded only on memory's remote, the shape a take refuses, is not one
  that `/gitlore:resolve` checks or `revert-pin` reverts, since both read the
  local index and `live`: the recording checkout's `/gitlore:push` is the
  remedy, and with that checkout gone nothing in the plugin is known to revert
  it.
- **The parent's pin on memory.** The report says the memory holding it has not
  been merged upstream, with no command and no url change. A contributor's pull
  request carrying only the pin is out of reach until their memory is merged;
  one carrying the url too is reachable once `git submodule sync` moves origin
  to their repo, and accepting that url, like whether the parent push refuses to
  publish such a pin, belongs to the multi-repo design.

The commit's pin refusal names `/gitlore:merge` for a pin the tier does not
hold, and prints no `checkout --detach <pin>` for a pin it cannot check out.

### The revert

`resolve.sh revert-pin <tier>` reverts, on memory's `live`, the commit that
recorded the tier at the lost commit. It is a revert and never a reset, so the
commit stays in history and the root lines it carried go with it. A holder found
alive afterwards sits ahead of the reverted pin, and the compose re-adopts its
lines. It refuses, saying why and changing nothing, when

- the tier is not checked out, or a store is mid-merge, or memory has
  uncommitted changes (the tier paths excepted, since the lost tier is off the
  recorded commit by definition and a revert writes no tier's worktree); the
  uncommitted-changes refusal prints the stash, revert and stash-pop commands,
  since a memory commit is refused over the lost pin;
- memory's `HEAD` is not on its `live`;
- `live` records no commit for the tier, the tier holds the commit after a fetch
  (then `/gitlore:merge` is the remedy), the fetch of the tier's remote failed
  (a remote with no `live` yet is not a failure), or no commit on `live` records
  the tier at it;
- the recording commit is a merge commit, which is reverted by hand with
  `git revert -m 1`;
- the revert does not apply cleanly, in which case it is abandoned and memory is
  as it was.

On success the local `live` advances and the message lists every path the
reverted commit changed, the revert undoing them all, with the command that
shows the full diff. Publishing the revert is `/gitlore:push`'s.

## Decisions — D79

**D79 — An unresolvable pin is an integrity error at every level**

A recorded commit that the repository which should hold it lacks composes
nothing and has nothing recorded under it. Two ways to get there exist for a
tier gitlink: `gitlore_push_stores` pushes every tier before memory and stops on
a tier failure, so only `--no-verify` or a raw push in memory records a tier
commit its remote never received; and a tier remote that lost the commit. The
parent's pin is reached by a pull request that carries a pin its memory has not
published.

My human partner's calls. The take still takes the tiers, then refuses the root
merge without moving or composing anything, and the compose takes no fallback
base. For a holder that no longer exists `/gitlore:resolve` reverts the *whole*
memory commit on `live`, never a reset, so the root lines the lost tier commit
carried go with it; the whole commit still goes when it carries fact edits or
other tiers' gitlinks too, and the success message lists every path the revert
changed, the full diff staying reachable from the reflog. One rule covers the
parent's pin on memory, with the remedy differing by level because only the tier
gitlink has a checkout that can publish it.

## Rejected alternatives

**A fallback base for the compose.** An empty or nearest-ancestor base would
read every line root dropped as one the tier added, or merge against a carrier
root never saw. The compose composes nothing instead (D79).

**Resetting memory's `live` past the recording commit.** It rewrites history the
other checkouts hold and drops the commit's fact edits silently. A revert keeps
the commit in history and lists what it undid (D79).

**Reverting only the gitlink line.** The root lines the lost tier commit carried
would stay in root, describing files no repository holds (D79).

**A command or a url change for the parent's pin.** Whether to accept another
repo's url belongs to the multi-repo design, and no command here makes a commit
exist that its memory has not published (D79).

**Reporting a healthy state over the pin.** The state is an integrity error: a
`/gitlore:resolve` that publishes or merges past it spreads the dangling record
(D79).
