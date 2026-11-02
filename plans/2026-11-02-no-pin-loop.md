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
| Tier ahead of root's pin (`HEAD` or local `live` holds commits past it) | Report: `gitlore-compose --up <tier>` or `/gitlore:merge` |
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
- The put-back in `gitlore_compose_check_pins`
  (`scripts/lib/index-compose-check.sh:255`): it reports and refuses. This also
  fixes the half-landed commit retry, which today rewinds the tier at
  `commit-memory.sh:129` and silently loses the carrier's line (p4i); the
  existing fixture misses it for want of a local `live`, so red pins it.
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

## Open

1. **Make both "tier ahead" remedies work.** Neither does as it stands: for
   `HEAD == live` past the pin, `/gitlore:merge` exits 0 and adopts nothing, and
   `gitlore_compose_up` stages nothing, so the commit still refuses. Default:
   the take also adopts when `HEAD` strictly contains the pin and the tier is
   clean, and `gitlore-compose --up <tier>` stages root's index and the tier's
   gitlink. A dirty tier ahead of its pin has `--up` as its only way out.
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
5. **A tier on its pin with local `live` ahead** arises by a refused adoption or
   an unadoptable merge, is silent today, and has no other prompt. Default: the
   killed-take branch stays as this report, whether or not a compose is pending,
   naming `/gitlore:merge`.

## Docs

D17 (pin model), D59, D74, and the merge and resolve skills.
