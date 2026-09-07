# Item 1.1 slice 1 — code review

Dispatch (d). Subject: the hunk `f6ef928` added to `gitlore_sync_memory_to_live`
in `scripts/lib/resolve.sh`, and its interaction with the surrounding function.

Verdict: one major finding, fixed in place. Nothing else changed.

## Major — compose writes into a tier before that tier's stale-merge guard runs

`gitlore_sync_memory_to_live` guards **memory** against a half-finished merge at
the top of the function. Each **tier** is guarded by
`gitlore_guard_stale_merge_state "$tierpath"`, the first statement in
`gitlore_sync_tiers_to_live`'s loop body — which the new compose call now runs
ahead of. Composition writes carrier files inside the tier worktrees, so the
window between the two is a write into a store the guard is about to refuse the
commit over.

`gitlore_compose` does not close the window itself:

- `gitlore_compose_check` implements rules 1, 2, 3, 4 and 6. None of them looks
  at merge state.
- `gitlore_compose_check_pins` (rule 7) has the mid-merge branch, but it is
  reached only after `[ "$head" = "$pinned" ] && continue`. A tier whose HEAD
  still sits on the commit memory's index records never reaches it.

A gitlore-prepared merge moves HEAD onto the authority ref
(`gitlore_prepare_merge` checks out before it merges), so rule 7 catches that
one. A merge gitlore did **not** prepare — the `orphaned-merge-head` case the
guard exists for, "a hand-run `git merge`, or an agent asked to merge by hand" —
leaves HEAD where it was, so `head = pinned` holds and compose proceeds.

### Reproduced, not inferred

Fixture: the slice's own, plus `MERGE_HEAD` planted in the tier's gitdir at the
tier's current HEAD (`head = pinned` confirmed in the run), driven through
`commit-memory.sh`.

Before the fix — the commit is refused, and the refusal's own words are false:

```
rc=1
gitlore: memory/ddaanet holds a merge gitlore did not prepare (MERGE_HEAD …),
so nothing was changed. …
carrier on disk: - [shared](shared.md) — fresh hook     ← compose rewrote it
```

The carrier went in as `stale hook`. Composition projected the root index's text
over a store holding an uncommitted merge — the silent overwrite of approved
upstream facts that D31/D36 and rule 7 exist to prevent — and then the run
reported that nothing had been changed.

After the fix: same `rc=1`, byte-identical message, carrier still `stale hook`.

### The fix

`scripts/lib/resolve.sh`, immediately before the compose call: run the same
per-tier guard there, ahead of the first write.

```sh
    local tier
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      [ -e "$mempath/$tier/.git" ] || continue
      gitlore_guard_stale_merge_state "$mempath/$tier" || return 1
    done < <(gitlore_tier_paths "$mempath")
```

Why this shape rather than a merge-state test of its own: the guard's verdict is
not the same as `gitlore_detect_stale_merge_state`'s reading. A
`stale-no-merge-head` state is *repaired* and returns 0, and the commit carries
on — so a raw detection would skip the compose on a store whose commit proceeds,
silently breaking this slice's external contract. Running the guard itself keeps
the two answers the same one.

The guard inside `gitlore_sync_tiers_to_live` stays. It is that function's
documented precondition, and it is not a repeated repair: every `return 0` path
out of `gitlore_recover_stale_no_merge_head` goes through
`gitlore_drop_merge_preparation`, so the second call detects `clean` and costs
one `rev-parse --git-dir` and one `[ -f ]`.

No new refusal: any tier state that stops the commit now already stopped it a
few lines later. The `.git` guard on the loop is the one
`gitlore_sync_tiers_to_live` and `gitlore_memory_stores` both carry — `git -C`
into an unmaterialized submodule answers for the enclosing repo. Line-based
`read -r` over `gitlore_tier_paths` matches the existing consumer; that helper
is NUL-delimited internally, so a tier path with spaces survives, and one with a
newline is out of scope by construction (its own comment says why).

### Open: the fix is not encoded in the suite

The two test files are out of scope for this dispatch, so the case is not added.
It is proven, and it is worth the orchestrator folding into
`tests/commit_memory.bats` alongside the slice's own case:

```bash
@test "a tier holding a merge gitlore did not prepare is not composed into" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  # HEAD stays on the commit memory's index records, so rule 7 does not fire;
  # a hand-run `git merge` leaves exactly this.
  gd=$(cd memory/ddaanet && cd "$(git rev-parse --git-dir)" && pwd)
  git -C memory/ddaanet rev-parse HEAD > "$gd/MERGE_HEAD"

  run bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 1 ]
  # The refusal says nothing was changed; the carrier has to bear that out.
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — stale hook'
}
```

## Checked and sound — no change made

- **Placement against the freshness check.** The compose sits after
  `gitlore_commit_msg_freshness` has already been read into `$fresh`. Since that
  helper takes the newest mtime under `$mempath` — which includes the tier
  worktrees — a compose ahead of it would refuse every commit as stale.
  `gitlore_sync_tiers_to_live` does not re-check freshness, so the carrier
  writes cannot invalidate the approval later in the run either.
- **Placement against the tier sync and the `add -A`.** Verified by mutation
  rather than by reading (below).
- **Dependencies.** `gitlore_compose`'s transitive closure resolves entirely
  within `index-compose.sh` and `util.sh`, both in scope at both entry points
  (`resolve.sh:11` sources the first; both entry points source the second). The
  three cross-library names in `index-compose.sh` —
  `gitlore_get_frontmatter_description`, `gitlore_index_largest`,
  `gitlore_weld_repair` — appear only in comments. `gitlore_active_tier_scopes`,
  which does reach `index-sync.sh`, is called from `gitlore_compose_and_report`
  only, which this path does not use. No new source line is needed.
- **Shell options.** All five compose callers — the three existing ones and both
  commit entry points — run under `set -euo pipefail`, so the call introduces no
  new option context for compose's internals. The `|| true` also keeps the call
  errexit-safe in `commit-memory.sh`, where the enclosing function is invoked
  bare rather than behind `|| exit $?`.
- **Hook environment.** Both entry points
  `unset $(git rev-parse --local-env-vars)` before sourcing, so
  `gitlore_compose_write`'s `rev-parse --absolute-git-dir` and
  `gitlore_compose_check_pins`' index read (`:$tier`) resolve against the right
  store.
- **Quoting and portability.** `"$mempath"` quoted; no GNU-isms, no bash-4
  constructs added. `shellcheck -s bash scripts/lib/resolve.sh` clean.

### Does the placement foreclose slice 3? No

Slice 3 replaces one line in place: `out=$(gitlore_compose "$mempath") || rc=$?`
followed by the `case` over 0/1/2. Both the rc-1 report-and-continue and the
rc-2 abort land at this position with nothing moved: the abort returns before
`rm -f "$msgfile"`, so the approved summary survives an aborted commit. The
`>/dev/null` is what slice 3 swaps for a capture, which is where the refusal
text comes from.

## Test evidence

- Baseline:
  `scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`
  → 24 passed, 0 failed.
- Mutation (one run, in place, restored afterwards): the compose call moved to
  *after* `gitlore_sync_tiers_to_live`. Both slice cases redded on
  `assert_bullets`, `want: — fresh hook` / `got: — stale hook`, 22 passed 2
  failed. So the tests red on the behaviour and on the ordering, not merely on
  the call's presence. `scripts/lib/resolve.sh` restored from HEAD and confirmed
  identical.
- After the fix: `commit_memory`, `git_hook_pre_commit`, `tier_lockstep`,
  `tier_divergence`, `resolve_recovery`, `resolve_merge_local`, `merge_memory`,
  `integration_memory_gate` → 98 passed, 0 failed. `resolve_compose`,
  `index_compose`, `push_behind_vs_diverged`, `resolve_merge_remote`,
  `resolve_merge_briefing` → 91 passed, 0 failed.
- `just precommit` not run; the orchestrator owns the gate.

The mid-merge probe was a scratch `.bats` file under `tests/`, run and deleted
in the same call; `git status --short` after each run shows the tree carrying
only the `scripts/lib/resolve.sh` edit.

## Not touched

The `|| true` placeholder and its comment, slice 2's dirty-only guard, both test
files, every pre-existing case in either suite, the `just format-docs` rewrap
the commit carried, `docs/`, and Phases 2 through 4.
