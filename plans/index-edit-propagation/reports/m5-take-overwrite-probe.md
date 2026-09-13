# M5 probe: does the take path's failed-compose_up remedy overwrite a tier's newer text?

## Verdict

**Overwrite reproduced.** `gitlore_adopt_tier_into_root` stages (and, when the
store was clean beforehand, commits) the tier gitlink even when
`gitlore_compose_up` fails. Once staged, the tier is back "on its pin"
(`git rev-parse ":ddaanet"` equals the tier's new HEAD). Following the printed
remedy — fix the store, edit root `MEMORY.md`, let composition run again — calls
`gitlore_compose`, whose down projection unconditionally prefers root's bullet
text for any path root has a line for (`scripts/lib/index-compose.sh:522-523`,
`gitlore_compose_down`). Root's line was never updated (the failed `compose_up`
never wrote it), so the tier carrier's newer text is silently overwritten by
root's older text, and `gitlore_compose` reports success (`status 0`)
throughout.

This confirms `gitlore_adopt_recovered_merge`'s header comment
(`scripts/lib/resolve.sh:279-291`): staging alone puts the enclosing store's
index back in agreement with the tier's HEAD, so the next pass composes and its
down projection writes root's older text over a carrier holding facts root has
never seen. `gitlore_adopt_tier_into_root` skips the guard
`gitlore_adopt_recovered_merge` applies (return before staging on a failed
`compose_up`); it stages and commits unconditionally.

## Scenario

1. Mount tier `ddaanet`, seed carrier `fact.md` with "older description",
   `gitlore_compose` once so root also carries
   `- [fact](ddaanet/fact.md) — older description`. Commit the tier,
   `commit_memory_state` to pin it in memory's index (`old_gitlink`).
2. Simulate a completed fast-forward take: edit the tier carrier's `fact.md`
   line in place to "newer description" and commit inside the tier — the shape a
   real `/gitlore:merge` fast-forward leaves before
   `gitlore_adopt_tier_into_root` runs.
3. Plant a **real** `gitlore_compose_check` refusal in the root index: two
   bullets both pointing at `ddaanet/dup.md` (`duplicate pointer path`), the
   same defect `tests/index_compose.bats` uses for that rule. No stub of
   `gitlore_compose_up` — the failure is a genuine check refusal.
4. Call `gitlore_adopt_tier_into_root memory ddaanet 0 "$old_gitlink"` directly
   (the take's adoption tail; `root_dirty_before=0` so the bookkeeping commit
   path runs). Observe: it prints "the root index could not take tier 'ddaanet's
   lines ... Fix the store, then edit MEMORY.md to retrigger composition", exits
   0, root's `fact.md` line is unchanged, and the gitlink is nonetheless staged
   and then committed (nothing left in `git diff --cached`; `HEAD:ddaanet` now
   equals the tier's new HEAD; the index pin `:ddaanet` agrees).
5. Apply the printed remedy verbatim: delete the duplicate bullet from root
   `MEMORY.md`, append an unrelated line, run `gitlore_compose memory`.
6. Read the tier carrier's `fact.md` bullet afterward.

`compose_up` was made to fail with real input, not a stub: a duplicate pointer
path (`ddaanet/dup.md` seeded twice) in the root index, which
`gitlore_compose_check` (called by `gitlore_compose_up`) refuses via
`gitlore_compose_check_index`'s rule 1 — an ordinary, independently-plausible
store defect, not manufactured to target this fact.

## Observed carrier line

- Before the remedy compose: `- [fact](fact.md) — newer description` (the tier's
  own, upstream-provided text, untouched by the failed take).
- After `gitlore_compose` ran following the remedy:
  `- [fact](fact.md) — older description` — root's stale text, silently
  overwritten in, with `gitlore_compose` exiting 0.

## Gitlink staging

Staged (and, since the store was clean before the take, committed) by
`gitlore_adopt_tier_into_root` regardless of the `compose_up` failure:
`HEAD:ddaanet` after step 4 equals the tier's new HEAD, and the memory store's
index pin (`git rev-parse ":ddaanet"`) agrees with it — i.e. the tier reads as
"on its pin" to `gitlore_compose_check_pins`, which is exactly what lets the
later `gitlore_compose` proceed to the down projection instead of refusing.

## Probe source (deleted after the run; rerun by restoring this file to `tests/probe_m5_take_overwrite.bats`)

```bash
#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "M5: failed compose_up still stages the gitlink, and the later remedy compose overwrites the tier's newer text" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet

  # Agreement: tier carries "older description", compose mirrors it to root.
  seed_tier_bullet ddaanet fact.md "older description"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qxF -- '- [fact](ddaanet/fact.md) — older description' memory/MEMORY.md

  # Commit and pin the tier — the base every take starts from.
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -q -m "tier: older description"
  commit_memory_state "pin ddaanet at older description"
  old_gitlink=$(git -C memory rev-parse HEAD:ddaanet)

  # Simulated completed fast-forward take: tier HEAD now carries upstream's
  # NEWER description, committed inside the tier, not yet recorded in memory.
  sed -i.bak 's/older description/newer description/' memory/ddaanet/MEMORY.md
  rm -f memory/ddaanet/MEMORY.md.bak
  git -C memory/ddaanet commit -aqm "tier: newer description from upstream"

  # Real gitlore_compose_check refusal: a duplicate pointer path in root.
  seed_root_bullet "ddaanet/dup.md" "first"
  seed_root_bullet "ddaanet/dup.md" "second"

  run gitlore_adopt_tier_into_root memory ddaanet 0 "$old_gitlink"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the root index could not take tier 'ddaanet'"* ]]
  [[ "$output" == *"duplicate pointer path ddaanet/dup.md"* ]]

  # Root's fact.md line is untouched (compose_up never wrote it).
  grep -qxF -- '- [fact](ddaanet/fact.md) — older description' memory/MEMORY.md

  # Gitlink staged and committed anyway (D43's unconditional pin).
  new_head=$(git -C memory/ddaanet rev-parse HEAD)
  staged=$(git -C memory diff --cached --name-only)
  [ -z "$staged" ]
  committed_gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  [ "$committed_gitlink" = "$new_head" ]
  pinned=$(git -C memory rev-parse ":ddaanet")
  [ "$pinned" = "$new_head" ]   # "back on its pin"

  # The printed remedy, applied verbatim.
  sed -i.bak '/ddaanet\/dup.md/d' memory/MEMORY.md
  rm -f memory/MEMORY.md.bak
  printf '\n<!-- unrelated edit -->\n' >> memory/MEMORY.md

  run gitlore_compose memory
  [ "$status" -eq 0 ]

  # THE VERDICT.
  carrier_line=$(grep -F 'fact.md' memory/ddaanet/MEMORY.md || true)
  [ "$carrier_line" = "- [fact](fact.md) — older description" ]
}
```

Run with:
`cd /Users/david/code/gitlore && scripts/run-bats.sh tests/probe_m5_take_overwrite.bats`
(after restoring the file above to that path). Result at time of writing:
`bats: 1 passed, 0 failed`. Deleted afterward;
`git status --porcelain -- tests/probe_m5_take_overwrite.bats` is empty.
