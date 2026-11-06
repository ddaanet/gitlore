# No pin loop — plan

Status: revised after probes; every question under "Questions" is settled and
the plan is ready to execute. Runs after
`plans/2026-11-01-silent-tier-line-loss.md`. Base: `dev`. Evidence:
`/tmp/claude/nopin-probes.md`.

## Design

`SessionStart` stops moving modules: a module is the root memory store or a
tier. It clones a missing module, fetches read-only, and reports. Each report
carries a directive that works when followed, and nothing is fixed silently.

| State | At `SessionStart` |
|---|---|
| Module not materialized | `--init` it, so "clone the repo and run claude" works |
| Local against the authority's `live` | See "What a module reports" |
| Root's tier lines would change in a compose pass, a tier off its pin included | The existing pending report: `gitlore-compose` |
| A tier's index holds a line root does not | The existing orphan report, reporting without refusing |
| Module mid-merge | Report the command that completes the merge and the one that aborts it |

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
  want of a local `live`, so red pins it. The tier-behind branch stays and
  widens from the manifest's tiers to every mounted tier (question 4, p1i).
- `rest_unadopted_tier` in `scripts/lib/continuation.sh`, its call sites in
  `scripts/resolve.sh` and the continuation's "could not take tier's lines"
  branch (question 5).
- The on-pin guard around `gitlore_compose_pending` in the diagnostics.
- The per-tier root write, stage-pair commit and walk-back in
  `scripts/lib/resolve-adopt.sh` and `resolve-adopt-report.sh`: one compose and
  one commit at the end of the run replace them ("Take order and compose").

`add-tier`'s detach stays: the mount is what establishes the precondition.

## What the probes add

- Root mid-merge has no report of its own and needs detection. Both flavors and
  both stores complete with `resolve.sh continue-after-merge`.
- Abort: read `refs/gitlore/pending`, `git merge --abort` (tolerating a missing
  `MERGE_HEAD`), `checkout -q --detach <pending>`,
  `gitlore_drop_merge_preparation`. This restored the store in every flavor
  tested. It reports any untracked file a merger left, which it does not remove.
- Take order becomes tiers first, root last ("Take order and compose"). The
  headers of `scripts/merge-memory.sh` and `scripts/lib/resolve-merge-stores.sh`
  and the merge skill's description already say so. The root-first comment in
  `gitlore_merge_stores`, the two in `scripts/lib/resolve-push.sh:127,160`, the
  paragraph in `docs/references/merge-and-resolve.md` and the sentence in
  `tier-stores.md` go with their premise.
- Messages and comments that assume the loop or the put-back: the ahead-of-pin
  line in `index-compose-check.sh`, and the comments at `commit-memory.sh:126`,
  `index-compose-pending.sh`, `resolve-adopt.sh:14,79`,
  `resolve-adopt-report.sh:68` and `scripts/resolve.sh`.
- Fourteen existing tests pin the removals and are rewritten where they pin a
  refusal. No existing test covers the P2/P4 loop; the probes' fixtures
  (`/tmp/claude/nopin-sim/tests/probe_*.bats`, `helpers/probe-lib.bash`) are the
  red author's starting point.

## Take order and compose

Settled by my human partner. A take visits every tier first and the root last,
and writes root's index once, at the end of the run, in one bookkeeping commit
naming the tiers it moved. Today the root goes first and each tier take writes
root and commits the pair. Root-first exists only so that a per-tier bookkeeping
commit does not meet upstream root's equivalent commit as a divergence; with no
per-tier commit that premise is gone.

- Each tier still fast-forwards or merges on its own, and D52's arrival repair
  still runs per tier, before the root moves: the arrived carrier is checked
  alone with `gitlore_compose_check_index`, and the repair's retry rechecks the
  carrier, not a compose. Only the root write and the bookkeeping commit move to
  the end. The end compose writes root and no carrier; the next pass mirrors
  down as today.
- The root take meets each gitlink after its tier already moved. A gitlink only
  upstream moved git takes silently; one both sides moved conflicts; in both the
  answer is the tier's current `HEAD`, which the prepare stages into the pending
  merge after an ancestry check, before the merger is briefed (question 4), so
  the gitlink asks no judgement of the merger.
- The reconcile of a store's `HEAD` against its local `live` follows the same
  order, since it prepares root merges through the same function:
  `gitlore-merge` and `gitlore-push` reconcile and take each tier before root's
  reconcile. The check stays in `gitlore_prepare_merge`, so a root merge
  `/gitlore:resolve` prepares without visiting a tier gets it too: a gitlink the
  tier does not hold gets one fetch of the tier and is then unresolvable, and a
  tier `HEAD` that does not descend a gitlink it holds stops the prepare naming
  `/gitlore:merge`.
- The compose-up is a three-way merge, not the overwrite `gitlore_compose_up`
  does today. For each tier, `gitlore_index_merge` over base = the carrier at
  the gitlink the memory index holds, prefixed as root carries it; ours = root's
  block for the tier; theirs = the tier's carrier at its `HEAD`. The index, not
  `HEAD`, because staging a gitlink is how root records that it has seen the
  tier's version: a chunk resolved to either side or to neither then stands,
  where a base read from `HEAD` would rebuild the same chunk at every pass and
  commit. Bullets merge entry-wise by path, with a diff3 chunk only for a path
  both sides moved apart, under the labels D44 gives. A tier on its pin composes
  as today, since base equals theirs. Settled by my human partner: root's index
  is recomposed from the tiers once tiers and memory are both merged, and no
  carrier line is lost on the way. A root merge ends in the memory merge's
  continuation, which recomposes before its commit, while `HEAD` still records
  `OURS`, so base is the gitlink `OURS` held. After that commit the staged tier
  `HEAD` reads as the pin, and a carrier line neither root side held would be
  adopted by nothing.
- A compose-up left with markers writes root with them, stages the gitlinks of
  the tiers it merged and commits nothing. The run names the file and the lines
  and says to resolve the markers and commit memory; nothing walks back, since
  every tier is already where its take put it. `gitlore_compose_check_index`
  gains a marker rule, so the pending check, the pass and the commit refuse root
  until the markers are gone.
- The continuation of a tier merge lands the merge and composes nothing. The
  carrier check that keeps a defective merged carrier from landing (D52) stays,
  on the carrier alone. The compose runs at the end of the `gitlore-merge` or
  push run that follows.
- The pass `gitlore-compose` runs the same three-way for each tier off its pin,
  so a tier another checkout or a killed take moved composes like an arrival.

## Tier ahead of its pin

Settled by my human partner. A tier `HEAD` that strictly descends its pin is not
a fault. What is wrong, when anything is, is root's lines for the tier
disagreeing with the tier's index, and the three-way compose answers it: base is
the carrier at the pin, so a line only the tier changed is adopted, a line only
root changed stands, and one both changed carries a diff3 chunk. Neither side
wins by fiat. `/gitlore:merge` brings in changes from `live` and gains no
adoption step, and there is no `gitlore-compose --up`.

- The commit commits through a tier ahead and its `add -A` records the gitlink,
  which reverses an alternative D50 rejected. The tier's commits are recorded
  and published with no approved summary. A commit that a pass would change
  aborts and names `gitlore-compose`, as D50 has it; the pass runs the
  three-way.
- `gitlore_compose_pending` runs at commit and SessionStart with no ref test in
  front of it for this state. The orphan report
  (`scripts/lib/index-compose.sh:259`) also runs at both, because a line the
  tier added changes nothing in a pass, so the pending check does not see it.
- A killed take needs no marker: a tier it moved with root unwritten is a tier
  off its pin whose carrier holds lines root lacks, and the three-way adopts
  them at the next pass or take.

## What a module reports

Settled by my human partner, from the use case. After a successful fetch, each
module compares what it holds locally, `HEAD` and local `live`, with its
remote's `live`, not with the pin.

| Local against the authority's `live` | Report |
|---|---|
| Strictly behind | Hint `/gitlore:merge` |
| Strictly ahead | Hint `/gitlore:push` |
| Diverged | Hint `/gitlore:push`, which prepares the merge |
| `HEAD` forked from local `live` | Hint `/gitlore:push`, which prepares the merge |
| In sync | `in sync.`, and nothing else |

`in sync.` replaces `gitlore: memory ready.` and its `(detached at live)` form.

Settled by my human partner: a divergence always hints `/gitlore:push`, and
`/gitlore:merge` is hinted only when the take is a fast-forward plus the canned
bookkeeping commit. A divergence left unpublished makes every later upstream
update a merge instead of a fast-forward; pushing it lands the merge and
publishes it, and the next upstream update then reads as behind and hints
`/gitlore:merge`. The rule is D76.

A pin published on the remote needs no check of its own: a parent `git pull`
over unpublished memory reads as diverged, and over none as behind. Being ahead
of the pin says nothing, so memory published before the parent commit reads as
in sync.

Settled by my human partner: the authority is the remote's `live` when the fetch
brought it, and local `live` otherwise, which covers no remote, a failed fetch
and a remote with no `live` yet. The table stands against local `live` too,
memory and tier alike. A `HEAD` forked from local `live` hints `/gitlore:push`
whatever the authority: `gitlore_reconcile_one` prepares the `head-vs-live`
merge inside the push, with or without a remote, while `/gitlore:resolve` on a
memory with no remote first tries to create one and prepares nothing. A failed
fetch keeps its could-not-fetch line with git's reason in front of the table's
line, and a tier that fails its fetch reports its position like memory does
instead of its fetch alone. No remote adds no line.

**An unresolvable pin is an integrity error at every level.** A recorded commit
the repository that should hold it lacks, whether the parent's pin on memory or
memory's gitlink on a tier, composes nothing and has nothing recorded under it:
no compose reads it as a base, and no commit records the module below it at
another commit, so the pin never moves backward silently. `SessionStart` and
`/gitlore:resolve` name the commit and the remote that lacks it, plus the repo
`.gitmodules` names when that is a different repo. The remedy is per level. For
a tier gitlink the checkout that recorded it runs `/gitlore:push` (question 4).
For the parent's pin the report says the memory holding it has not been merged
upstream, with no command and no URL change: a contributor's PR carrying only
the pin is out of reach until their memory is merged, and one carrying the URL
too is reachable once `git submodule sync` moves origin to their repo, and
accepting that URL, like whether the parent push refuses to publish such a pin,
belongs to the multi-repo design. `/gitlore:resolve` does not say "healthy" over
it. By D64 `.gitmodules` records https while a module's own remote can stay on
ssh, so "a different repo" is not a string comparison. The commit's refusal
stops printing `checkout --detach <pin>` for a pin it cannot check out.

## Questions

All settled. Questions 1 to 3 are absorbed above: the tier-ahead remedies into
"Tier ahead of its pin", the invariant predicate into "What a module reports",
and resolve's scope into "An unresolvable pin".

4. **Older gitlinks.** A memory commit does nothing special about a tier another
   checkout moved: it leaves the pin alone, and what follows depends on `live`.
   If `live` equals `HEAD`, the commit advances `live`. If `live` has the other
   commit, the two have diverged and need a merge.

   Settled by my human partner: tiers first settles the merge. The tier moves
   before root does, so a pin only the other side moved is a tier fast-forward
   followed by a root merge whose gitlink git takes silently, and a tier with
   its own commit lands its tier merge first, after which the root merge records
   the tier's `HEAD` and the end compose carries both facts' lines into root.
   One `/gitlore:merge` loop takes everything, and the report names no line to
   delete. Reasoned from step10.log and step11.log, not re-run: red probes it
   first. A tier with uncommitted work is refused before anything moves, with
   commit first as the remedy (step10.log).

   Settled by my human partner: a tier gitlink on memory's `live` that does not
   resolve in the tier, locally or on its remote, is a data integrity error and
   propagates nowhere. `gitlore_push_stores` pushes every tier before memory and
   stops on a tier failure, so only `--no-verify` or a raw push in memory
   produces it. The take still takes the tiers, then refuses the root merge
   without moving or composing anything, and names the commit, the tier and the
   remote that lacks it, with the remedy that the checkout which recorded it
   runs `/gitlore:push`; the next `/gitlore:merge` retries. The compose takes no
   fallback base. For a holder that no longer exists, `/gitlore:resolve` reverts
   the whole memory commit on `live`, never a reset, so the root lines the lost
   tier commit carried go with it; a holder found alive afterwards sits ahead of
   the reverted pin and the compose re-adopts its lines. Settled by my human
   partner: the whole commit still goes when it carries fact edits or other
   tiers' gitlinks too, and the success message lists every path the revert
   changed; the full diff stays reachable from the reflog. One rule with the
   parent's pin on memory, under "An unresolvable pin" above.

   Settled by my human partner: a raw pull in memory that leaves a tier checkout
   behind the pin (p1i) is refused at the commit for every mounted tier, dormant
   included, since `add -A` would record the older commit silently. The guard
   loops over mounted tiers, not the manifest, and refuses a tier whose `HEAD`
   is a strict ancestor of the pin, naming `/gitlore:merge`, which fast-forwards
   it; a tier on or ahead of its pin passes. `SessionStart` reports the same
   state.

   Settled by my human partner: how the root merge records the tier's `HEAD`.
   After git's line-wise merge of `live`, for every mounted tier, the prepare
   checks that both `OURS` and `THEIRS` of the gitlink are ancestors of the
   tier's `HEAD`, which a tier merge commit and a fast-forward both satisfy,
   then stages the tier path into the pending `--no-commit` merge, so the
   unmerged entry is gone before the state file is written and the merger sees
   index and fact text only; the continuation's merge commit carries it. A tier
   failing the check stops the prepare before the merger is briefed, naming the
   tier.
5. **A tier on its pin with local `live` ahead** arises today by the
   continuation resting a tier whose merged lines the D50 adopt refused, and is
   silent afterwards. Settled by my human partner: dissolved. The continuation
   of a tier merge composes nothing and the end three-way has no refusal to
   fail, so the rest has nothing to produce it: `rest_unadopted_tier`, its call
   sites in `scripts/resolve.sh` and the continuation's "could not take tier's
   lines" branch go with the D50 adopt path. A tier found in that state anyway,
   from an arrival or a rest made before this plan, has `HEAD` behind the
   remote's `live`, which the report rule above hints `/gitlore:merge` for. No
   report is added.

## Docs

D17 (pin model), D50 and `docs/references/git-hooks.md` (the reversed
alternative), D59, D74, and the merge and resolve skills. The take order and
compose: the root-first paragraph and D49's per-take bookkeeping commit in
`merge-and-resolve.md`; D43's "composition places lines, it does not merge
them", the walk-back and the staged pair in `tier-stores.md`; D44's compose-up
call site in `tier-conflicts.md`; D52's continuation gate on the carrier alone
in `tier-arrival-repair.md`; `gitlore_compose_up`'s contract in
`index-composition.md`. From the questions: the unresolvable-pin rule and its
per-level remedies, with the revert in `/gitlore:resolve`, as a decision of its
own; the pin guard over mounted tiers in `git-hooks.md`; the rest's removal in
`tier-stores.md` and `merge-and-resolve.md`; the report authority, remote `live`
or local `live`, with the table, in the node the execution puts it in, since no
node documents the `SessionStart` report lines today, `workflows.md` and
`merge-and-resolve.md` only cite them; the prepare's gitlink stage in
`merge-and-resolve.md`.
