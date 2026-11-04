# No pin loop — plan

Status: revised after probes, awaiting my human partner's call on "Open". Runs
after `plans/2026-11-01-silent-tier-line-loss.md`. Base: `dev`. Evidence:
`/tmp/claude/nopin-probes.md`.

## Design

`SessionStart` stops moving modules: a module is the root memory store or a
tier. It clones a missing module, fetches read-only, and reports. Each report
carries a directive that works when followed, and nothing is fixed silently.

| State | At `SessionStart` |
|---|---|
| Module not materialized | `--init` it, so "clone the repo and run claude" works |
| Root ahead of the parent's pin | Silent: the latest is kept and nothing is lost |
| Root behind the parent's pin | The existing upstream-commits report: `/gitlore:merge` |
| Tier `HEAD` strictly descends root's pin | Silent: not a fault in itself. The next commit records the gitlink |
| Tier's take-in-progress marker matches `HEAD` | Report: `/gitlore:merge` finishes the interrupted take |
| Root's tier lines would change in a compose pass | The existing pending report: `gitlore-compose` |
| A tier's index holds a line root does not | The existing orphan report, reporting without refusing |
| Tier behind or diverged from root's pin, pin reachable | Report: `/gitlore:merge` |
| Module mid-merge | Report the command that completes the merge and the one that aborts it |
| Pin diverged from `live`, or its object absent | Report an invariant violation naming `/gitlore:resolve` |

A store is detached. A store attached to any branch, `live` included, breaks a
precondition and gets no handling: all 38 real stores on this machine are
detached, and `init-submodule.sh` and `add-tier.sh` both detach. A missing local
`live` is normal on a fresh clone and is no violation.

## What goes

- The re-pin in `gitlore_sync_nested_tiers` (`scripts/lib/session-tiers.sh:66`):
  `submodule update --init` runs only for an unmaterialized tier. The detach at
  `:74` goes, and so does the merge guard's `continue`. Its notice stays, as the
  mid-merge row's report for a tier.
- The memory store's detach at `scripts/cc-hooks/session-start.sh:195-197`.
- The put-back and the whole tier-ahead branch in `gitlore_compose_check_pins`
  (`scripts/lib/index-compose-check.sh:255`). This also fixes the half-landed
  commit retry, which today rewinds the tier at `commit-memory.sh:129` and
  silently loses the carrier's line (p4i); the existing fixture misses it for
  want of a local `live`, so red pins it.
- The on-pin guard around `gitlore_compose_pending` in the diagnostics.

`add-tier`'s detach stays: the mount is what establishes the precondition.

## What the probes add

- Root mid-merge has no report of its own and needs detection. Both flavors and
  both stores complete with `resolve.sh continue-after-merge`.
- Abort: read `refs/gitlore/pending`, `git merge --abort` (tolerating a missing
  `MERGE_HEAD`), `checkout -q --detach <pending>`,
  `gitlore_drop_merge_preparation`. This restored the store in every flavor
  tested. It reports any untracked file a merger left, which it does not remove.
- Take order is root first. Correct `scripts/merge-memory.sh`, the
  `scripts/lib/resolve-merge-stores.sh` header and the merge skill's
  description.
- Messages and comments that assume the loop or the put-back: the ahead-of-pin
  line in `index-compose-check.sh`, and the comments at `commit-memory.sh:126`,
  `index-compose-pending.sh`, `resolve-adopt.sh:14,79`,
  `resolve-adopt-report.sh:68` and `scripts/resolve.sh`.
- Fourteen existing tests pin the removals and are rewritten where they pin a
  refusal. No existing test covers the P2/P4 loop; the probes' fixtures
  (`/tmp/claude/nopin-sim/tests/probe_*.bats`, `helpers/probe-lib.bash`) are the
  red author's starting point.

## Tier ahead of its pin

Settled by my human partner. A tier `HEAD` that strictly descends its pin is not
a fault. What is wrong, when anything is, is root's lines for the tier
disagreeing with the tier's index. Root is authoritative because it is what
memory recall reads; a tier's index only carries lines between projects.
PostToolBatch handles propagation and merges handle `gitlore_compose_up`, so a
tier ahead with an index out of sync takes an act outside the system, and root
winning is the right answer to it. `/gitlore:merge` brings in changes from
`live` and stays out of this: its adoption is not widened, and there is no
`gitlore-compose --up`.

- The commit commits through a tier ahead and its `add -A` records the gitlink,
  which reverses an alternative D50 rejected. The tier's commits are recorded
  and published with no approved summary.
- `gitlore_compose_pending` runs at commit and SessionStart with no ref test in
  front of it for this state. The orphan report
  (`scripts/lib/index-compose.sh:259`) also runs at both, because a line the
  tier added changes nothing in a pass, so the pending check does not see it.

**A killed take is the exception**, since its tier holds approved upstream lines
root has not adopted, and root winning would lose them. It gets a marker naming
the target commit, in the tier's gitdir beside `gitlore-merge-state`, written
before the tier moves and removed once root's index is updated:

- Marker matches `HEAD`: the tier's index is authoritative. The compose pass and
  the commit refuse and name `/gitlore:merge`, and SessionStart reports it.
- Marker does not match `HEAD`: the tier did not move, root is authoritative,
  the gates ignore the marker and merge drops it.
- Every tier move in a take writes it first: the fast-forward, the adoption from
  local `live`, and the arrival repair, which rewrites it before moving past the
  arrival. The landed-merge continuation needs none: its state-file recovery
  re-adopts.
- Recovery is the per-tier step of `/gitlore:merge`, ahead of its "already holds
  everything" exit, through `gitlore_adopt_tier_into_root`. It does not refuse a
  dirty tier: no checkout is needed and the commit is refused in this state, so
  a refusal would be a dead end.
- Recovery compares root's lines for the tier against root at `HEAD` and the
  tier's index. Equal to the tier's index: the update already happened, so it
  drops the marker. Equal to root at `HEAD`: it updates root. Different from
  both: it refuses, lists the lines, and says to undo those edits, run
  `/gitlore:merge` and make them again. An entry-wise three-way merge
  (`gitlore_index_merge`) is not worth its code on a path this rare.

## Open

2. **Invariant predicate.** "Pin not an ancestor of `live`" also matches every
   behind state, including a plain parent `git pull`. Default: classify the pin
   against `live`; descendant is the behind row, and only diverged or an absent
   object is the violation.
3. **Resolve's scope.** It reads no pin today, says "healthy" over the
   violation, and publishes while doing so. Default: it detects the violation
   and refuses, publishing nothing. It names `checkout --detach <pin>` then
   `/gitlore:merge` when the object exists, the one path that lands it (p3t2),
   and otherwise says the pin's commit is on no reachable remote. No automatic
   repair.
4. **Older gitlinks.** `gitlore-commit` records an older gitlink for a dormant
   tier, and removing the loop strips its only protection (p1i). Default: the
   pin guard covers every mounted tier, in this plan.

   A memory merge moves a tier backward too, on an active tier, and that guard
   does not reach it. You run `/gitlore:merge`, `/gitlore:resolve` or a push in
   a checkout whose memory has diverged from a remote recording a newer commit
   of a tier than this checkout holds. The merge lands with exit 0 and records
   this checkout's older commit, undoing a tier move nobody asked to undo.
   Nothing names this: you see an index line reported as pointing at a missing
   file, with a remedy to delete the line, or nothing when the newer commit
   added no line.

   The next `/gitlore:merge` repairs it when the tier's remote has the newer
   commit, and so does a push when the tier has a local `live`. A fresh clone's
   tier has none, so its push publishes the older commit as the memory remote's
   tip, and a merge `/gitlore:resolve` prepares publishes it as it lands.
   Another checkout that takes that tip then loses the fact's file from its tier
   at its next session, until it runs `/gitlore:merge` again. When the tier's
   remote lacks the newer commit, `/gitlore:merge` says it already holds
   everything and the push publishes the older commit. A memory commit made
   first records the older commit again. If the newer commit added an index
   line, that commit is refused until compose writes the line into the old tier,
   which forks the tier and costs a tier merge. A session started between
   preparing and landing moves the tier forward, so the merge records the newer
   commit; removing the loop strips that too.

   Default: when this checkout's tier is behind the commit the other side of the
   merge records, the merge keeps that newer commit, in this plan. The tier is
   then behind its pin, the table's behind row, and `/gitlore:merge` takes it.
   When the tier's remote lacks that commit, the state is question 3's
   violation.
5. **A tier on its pin with local `live` ahead** arises by a refused adoption or
   an unadoptable merge, is silent today, and has no other prompt. Default: the
   killed-take branch stays as this report, whether or not a compose is pending,
   naming `/gitlore:merge`.

## Docs

D17 (pin model), D50 and `docs/references/git-hooks.md` (the reversed
alternative), D59, D74, and the merge and resolve skills.
