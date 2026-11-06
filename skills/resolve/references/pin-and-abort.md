# An unresolvable pin, and abandoning a prepared merge

Two outcomes of `/gitlore:resolve` that carry no sub-agent dispatch. Read this
when the resolver's output names a commit that no repository holds, or when the
user asks to abandon a merge that is prepared.

## An unresolvable pin

The resolver's exit 1 without `gitlore: memory merge prepared` can be an
integrity report: a recorded commit that the repository which should hold it
lacks. It is raised before any push or merge gate, so nothing was published past
it, and the resolver does not say the state is healthy. Two shapes:

- **A tier gitlink.** The line reads `gitlore: memory records tier '<t>' at
  <sha>, a commit …` and says whether neither the tier nor its remote holds it,
  or the tier has no remote, and names the repo `.gitmodules` records when that
  is a different one. Nothing composes over the commit. The checkout that
  recorded it runs `/gitlore:push`, which publishes it. If the user says that
  checkout no longer exists, the report's second line holds the command that
  reverts the memory commit which recorded it:

  ```bash
  cd "<repo>" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh" revert-pin <tier>
  ```

  Run it only after the user confirms no checkout holds the commit. It reverts
  the whole memory commit on `live`, never a reset, so the commit stays in
  history and the root lines it carried go with it; it refuses, changing nothing,
  when memory has uncommitted changes, when `HEAD` is not on `live`, when a merge
  is prepared, or when the recording commit is a merge commit (its message gives
  the `git revert -m 1` form). Its success message lists every path the commit
  changed, including fact edits and other tiers' gitlinks; relay that list and
  tell the user to run `/gitlore:push` to publish the revert. A holder found
  alive afterwards sits ahead of the reverted pin, and the next compose re-adopts
  its lines.
- **The parent's pin on memory.** The line reads `gitlore: this repository
  records memory at <sha>, …` and says the memory holding it has not been merged
  upstream. No command applies, and no url should be changed on the report's
  say-so: relay it and stop.

The urls in these reports reach the user's line only; the agent's line says the
user has them. Do not ask for them or reconstruct them.

## Abandoning a prepared merge

A prepared merge that has not landed is abandoned with the abort command the
session-start report names:

```bash
cd "<repo>" && bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh" abort-merge
```

It works on the memory root's merge, restores the store to the commit the merge
started from under git's `reset --merge` contract, and drops the preparation. It
discards the merge's staged result, so run it only when the user asks to abandon
the merge, never to clear an obstacle. It refuses, saying why, when no merge gitlore
prepared is there or the store cannot be returned. The next `/gitlore:merge` or
`/gitlore:push` prepares the merge again if the divergence is still there.
