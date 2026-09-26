# GREEN — a tier's prepared merge outranks the summary screens too

## The four tests

- `tests/cc_hook_memory_commit_batch.bats` — "a tier's prepared merge hands over
  the merge directive, not a re-approval request": passes now that the post-run
  arm checks `gitlore_any_store_mid_merge` instead of `gitlore_store_mid_merge`,
  so the tier's own `MERGE_HEAD` is found and `$out` (the guard's merge
  directive) is handed over instead of falling to the freshness arm.
- `tests/cc_hook_memory_commit_batch.bats` — "a tier mid-merge with no approval
  is not met with a request for a summary": passes for the same reason on the
  pre-run screen — `mid_merge` is now computed from
  `gitlore_any_store_mid_merge`, so the no-approval screen is skipped and the
  run below re-emits the merge directive.
- `tests/commit_memory_approval.bats` — "a tier mid-merge is answered with the
  merge directive, not a summary request": passes now that `commit-memory.sh`
  loops `gitlore_tier_paths` after its own root `gitlore_guard_stale_merge_state`
  call and runs the same guard against every materialized tier, so the tier's
  prepared merge is answered before the "Pass it with -m" screen.
- `tests/commit_memory_approval.bats` — "the usage line names the bare
  invocation": passes now that the usage string reads
  `usage: commit-memory.sh [-m <summary> | -F <file> | -F - | bare]`.

## Pass/fail counts

`./scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats tests/commit_memory_approval.bats`
→ `bats: 26 passed, 0 failed` (17 + 9, every pre-existing test in both files
still passes).

## Production changes

- `scripts/lib/util.sh` — new `gitlore_any_store_mid_merge`, sited directly
  after `gitlore_store_mid_merge`. Composes the existing predicate over the
  root and every mounted, materialized tier, mirroring the tier loop shape in
  `resolve-sync-memory.sh:42-47`/`:86-92`. `gitlore_store_mid_merge` is
  unchanged; `index-compose-check.sh:215` still calls it directly.
- `scripts/cc-hooks/memory-commit-batch.sh` — both mid-merge reads (pre-run
  `mid_merge=…` and the post-run `elif` arm) now call
  `gitlore_any_store_mid_merge`. The post-run arm's wording is qualified (see
  below).
- `scripts/commit-memory.sh` — after the existing root
  `gitlore_guard_stale_merge_state "$mempath"` call, a new loop over
  `gitlore_tier_paths "$mempath"` runs the same guard against every
  materialized tier (`[ -e "$mempath/$tier/.git" ]`), before the
  `gitlore_approval_present` screen. Usage string updated to list the bare
  form.

## Qualified mid-merge wording

The post-run arm in `memory-commit-batch.sh` previously said "the memory store
holds a prepared merge" — imprecise once a tier can be the one holding it.
Both the `systemMessage` and the `additionalContext` now read "the memory store
or a mounted tier holds a prepared merge" (verbatim: `gitlore: memory commit
deferred — the memory store or a mounted tier holds a prepared merge. $out` /
`gitlore: the memory commit did not run: the memory store or a mounted tier
holds a prepared merge, which is answered before any commit. …`).

Doc wording qualified the same way in `docs/references/commit-gate.md` ("The
store **or any mounted tier mid-merge**…", "**A prepared merge on the store or
any mounted tier outranks that screen**…") and
`docs/references/memory-entry-points.md` ("dirty with the store or any mounted
tier mid-merge → …").

## check-docs-links.py — BLOCKED, out of scope

`./scripts/check-docs-links.py` is **not** clean:

```
BLOCK oversized-file       tests/cc_hook_memory_commit_batch.bats:455: 455 lines, over the 400-line cap
oversized-file       1
```

This is pre-existing from the RED phase, not introduced by this GREEN slice:
`git stash` back to the unmodified HEAD (before RED's uncommitted test edits)
shows `check-docs-links` fully clean (`oversized-file 0`). RED's two new tests
plus the `load helpers/tier-fixtures` line added ~66 lines to a file that was
already at 389 of the 400-line cap, landing it at 455 — 55 over. My dispatch's
scope explicitly excludes editing this file's test bodies (only
`tests/commit_memory_approval.bats`, and only to delete one stray blank line,
was in scope), so I have not touched it. `scripts/lib/util.sh` had the same
problem from my own addition (386 → 405) and I trimmed the new function's
comment to land the file at exactly 400; that fix was in scope and I made it.
The bats file needs either a split or a trim of its own, which is a test-body
decision outside this dispatch's scope — flagging rather than fixing.

## shellcheck

`shellcheck scripts/commit-memory.sh scripts/cc-hooks/memory-commit-batch.sh scripts/lib/util.sh`
→ clean (rc 0).

## just precommit — did not complete

Ran in background (`run_in_background: true`), completion notification
received: **failed, exit code 1**. The tail of its output shows `format-docs`
ran (fixed 13/57 issues in 3 files — the changelog and doc rewraps), then
`check-memory-hygiene.py` ran clean (0 blocking, 14 `deictic` warnings,
pre-existing), then `check-docs-links.py` hit the oversized-file block above
and the recipe aborted there with `error: Recipe precommit failed with exit
code 1`. Read from the log tail at
`/tmp/claude-1000/-Users-david-code-gitlore/908a9b99-5d74-4ce9-8ae6-4af494c6d049/tasks/bzwppjtju.output`.

Because `check-docs-links.py` runs ahead of `just check-version lint test` in
the `precommit` recipe body, **lint, test-unit and test-integration never
ran this pass**. Their gate sentinels under
`$(git rev-parse --git-path gitlore/gates)` are stale (timestamped ~2 hours
before this run) and do not vouch for the current tree. `check-distribution`'s
own gate did update fresh in this run (its sentinel changed), since it runs
before the failing check.

Outside the `precommit` recipe, run separately as a substitute check:
`shellcheck` (above, clean) and the two target bats suites (above, 26/0). Full
`lint`/`test-unit`/`test-integration` have not been re-verified against this
change.

## Not committed

Per the dispatch's own instruction ("Never `--no-verify`... STOP and report it
— do not invent an approval summary") and done-criterion 4, I have not
committed. The tree still holds the diffs listed above, uncommitted, plus the
new changelog entry file.
