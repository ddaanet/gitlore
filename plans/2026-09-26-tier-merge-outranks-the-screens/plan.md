# A tier's prepared merge outranks the summary screens too

2026-09-26. Closes M1 and M2 of
`git show a274b4c:plans/batch-retry-approval-freshness/reports/deliverable-review.md`,
plus the third site that review's probe found afterwards.

## The defect

`16c15e9` ordered a prepared merge ahead of the summary screens on both commit
entry points, but every one of its tests reads
`gitlore_store_mid_merge "$mempath"` — the **root** store only.
`gitlore_sync_tiers_to_live` prepares a head-vs-live merge
**in the tier's gitdir** (`scripts/lib/resolve-sync-tiers.sh:90`), so with a
tier mid-merge the root is not mid-merge, every bypass misses, and three sites
answer wrongly. All three are confirmed by running the state, not by reading:

1. `scripts/cc-hooks/memory-commit-batch.sh:164` — the tier's merge checkout
   writes content newer than the approval, freshness reads `no`, and that arm
   deliberately drops `$out`. The agent gets
   `the approved summary no longer covers the store, approval needed again` and
   the `gitlore: memory merge prepared (flavor=head-vs-live)` directive — the
   `gitlore:memory-merger` dispatch, the `continue-after-merge` command, and the
   string the `gitlore:resolve` skill description triggers on — is discarded.
   Self-heals on the next batch, after a wasted approval turn.
2. `scripts/cc-hooks/memory-commit-batch.sh:96,100` — with no approval on disk
   the pre-run screen fires, putting a merge both of whose sides are already
   approved (D49) in front of the user as a summary to draft.
3. `scripts/commit-memory.sh:72,75` — bare, tier mid-merge, no approval file:
   `gitlore: memory is dirty; commit-memory needs an approved summary.`

In all three the closing promise (`the commit then completes on its own`) is
false: a summary written in response still meets the tier guard.

`gitlore_sync_memory_to_live` is already tier-aware where it screens
(`scripts/lib/resolve-sync-memory.sh:42-47` loops `gitlore_tier_paths`), which
is why the stale-approval path on the script entry point is correct today.

## Design

**One tier-aware predicate, used wherever the root-only one screens.**

- `scripts/lib/util.sh` — add `gitlore_any_store_mid_merge`, next to
  `gitlore_store_mid_merge`: exit 0 when the memory store
  **or any mounted tier** holds an unfinished merge. It composes
  `gitlore_store_mid_merge` over `$mempath` and each `gitlore_tier_paths` entry,
  skipping a tier whose worktree is not materialized
  (`[ -e "$mempath/$tier/.git" ]`) exactly as the sync's own loops do — `git -C`
  into an unmaterialized submodule walks up to the enclosing repo and answers
  for memory under the tier's name. `gitlore_store_mid_merge` stays:
  `index-compose-check.sh:215` asks about one named store and must keep doing
  so.
- `scripts/cc-hooks/memory-commit-batch.sh` — both reads (line 96 pre-run, line
  152 post-run) take the new predicate. The post-run arm keeps its ordering:
  consumed-approval, then mid-merge, then freshness, then deferred.
- `scripts/commit-memory.sh` — after the root `gitlore_guard_stale_merge_state`
  at line 72, loop `gitlore_tier_paths` and guard each materialized tier, the
  same shape as `resolve-sync-memory.sh:42-47`. The guard, not the predicate: it
  is the guard that emits the directive this path must hand over.

**Rejected.** Checking whether `$out` already carries a merge directive before
the freshness arm — prose as protocol, which D56 rejected by name.

## Also in this change

- `scripts/commit-memory.sh:28` — the usage string still reads
  `usage: commit-memory.sh [-m <summary> | -F <file> | -F -]`. Bare is a
  documented first-class mode and the form the batch hook uses; list it.
- `docs/references/commit-gate.md` — "A store **mid-merge**" (§ mechanism) and
  "**A prepared merge outranks that screen**, on both entry points" both read as
  covering a tier and do not. Say the store or any mounted tier.
- `docs/references/memory-entry-points.md` — the `commit-memory.sh` guard
  sentence ("dirty with the store mid-merge → the stale-merge guard's
  directive") takes the same qualification.
- `docs/decisions.md` — no new decision. This is D56/D49 applied where they
  already claimed to reach; the conclusion lines stand.
- `docs/changelog/` — one entry, named like its siblings, plus its
  `docs/changelog.md` index line.

## The tier-divergence fixture

Verified working during the review. Needs `load helpers/tier-fixtures` added to
both suites (neither loads it today):

```bash
make_tier_in_memory ddaanet
set_tier_manifest ddaanet
git -C memory/ddaanet fetch -q origin "live:live"
git -C memory/ddaanet checkout -q --detach live
advance_branch_with_file "memory/ddaanet" live other.md body "sideways" live
echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
```

A first run through the entry point under test is what prepares the merge;
assert `git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD` is non-empty
before the run that matters.

## Work

RED before GREEN, one dispatch each.

### RED — `tests/cc_hook_memory_commit_batch.bats`

- `a tier's prepared merge hands over the merge directive, not a re-approval request`:
  fixture above, approval + trigger, first batch prepares the tier merge (assert
  `MERGE_HEAD`); second batch asserts additionalContext contains
  `memory merge prepared` and `prepared merge`, and does **not** contain
  `no longer covers`; systemMessage is not the re-approval line; both IPC files
  stand and memory `HEAD` is unchanged.
- `a tier mid-merge with no approval is not met with a request for a summary`:
  same fixture, then `rm -f` the approval file before the second batch;
  additionalContext contains `memory merge prepared`, and does **not** contain
  `no approved summary exists yet` or `blockquote`; the trigger stands.

### RED — `tests/commit_memory_approval.bats`

- `a tier mid-merge is answered with the merge directive, not a summary request`:
  the sibling of the existing root-store test at line 116. Bare, no approval
  file; output+stderr contains `memory merge prepared` and does **not** contain
  `Pass it with -m`; memory `HEAD` unchanged.
- `the usage line names the bare invocation`: a bad operand exits 2 and the
  usage string mentions the bare form.

Each test must fail on unchanged code **at its own assertion** — not on a
missing helper, a load error or a fixture error. Record the failing assertion
and its message for every one.

### GREEN

The three code changes above, then the usage string and the four doc edits.
`scripts/check-docs-links.py` must stay clean.
