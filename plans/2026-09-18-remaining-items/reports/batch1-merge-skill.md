# Batch 1 — merge skill prose (Items A and B)

## Files changed

- `/Users/david/code/gitlore/skills/merge/SKILL.md` (+45/−6, now 107 lines)
- `/Users/david/code/gitlore/docs/references/index-composition.md` (+13, now 337
  lines)

Nothing else was touched. No commit, no branch, no push.

## Item A — the repair report is now three outcomes, not one claim

The `## Report` section's repair paragraph kept its first two sentences and now
closes with a three-bullet list plus a transient-failure sentence.

Claims verified, each against `scripts/lib/resolve.sh`:

- **The publish line is conditional.** `gitlore_adopt_repair_arrival` prints
  `gitlore: %s — the repair is committed in its local 'live'; /gitlore:push publishes it.`
  at `resolve.sh:2030`, *after* the retry `gitlore_compose_up` at 2022 returned
  0. The `GITLORE_TAKE_IN_PUSH` arm at 2028 prints the other wording, which
  `/gitlore:merge` never reaches. The skill now makes the claim conditional on
  the output ending `; /gitlore:push publishes it.` — the string is byte-exact
  in the script (`grep -cF` → 1).
- **The resting case publishes nothing until the local problems are fixed.** A
  refused retry goes to `gitlore_adopt_report_refusal_and_walk_back` at 2024
  with remedy `""` and `live_holds` `"the repair"`, so the run prints the root
  refusal (2065-2066), then
  `… its local 'live' keeps the repair. Fix the store, then run /gitlore:merge again.`
  (2092, with `gitlore_adopt_walk_back_tier`'s default remedy at 2081). Nothing
  was recorded and nothing was pushed.
  `docs/references/tier-arrival-repair.md:118` states the same: "A repair
  resting on local problems publishes nothing until they are fixed", and :116
  that a take inside a push publishes the repair — which is why the skill says
  `/gitlore:push` publishes it once the problems are fixed. The claim that the
  next take does not repair again is `tier-arrival-repair.md:93-95` and follows
  from the code: the next take's arrival is `live`, which now holds the repair
  and passes `gitlore_compose_check_index`.
- **The two unrepairable remedies.** `resolve.sh:1986` sets
  `Fix the problems listed above in this repo; once the index is fixed where it was published, run /gitlore:merge again.`
  when the same refusal named indexes other than the carrier (`other_lines`
  non-empty, built at 1979-1985), and 1988 sets
  `Once the index is fixed where it was published, run /gitlore:merge again.`
  otherwise. Both are byte-exact (`grep -cF` → 1 each). The skill now carries
  both and says which one applies.
- **The transient remedy.** `Run /gitlore:merge again.` is passed at
  `resolve.sh:1955` (no scratch dir), 2001 (no repair built — reached from the
  arrival read, the pin read, the rewrite and the commit build), 2007 (`live`
  advance refused) and 2012 (the checkout that follows it). Four occurrences,
  byte-exact. The skill now names those failure points and relays the remedy,
  with the script's own reason — the next take repairs from scratch
  (`tier-arrival-repair.md:66-67`).

The review's Major 1 ("Major Findings" 1 of
`plans/unadoptable-tier-arrival/reports/deliverable-review-prose.md`) asked for
exactly these three changes; its evidence matches what the script shows.

## Item B — the memory fact's content moved into the plugin

`memory/ddaanet/gitlore-tier-merge-direction.md` was read only. It was not
edited or deleted.

**Mechanism → `docs/references/index-composition.md`, D36.** I read both
candidate nodes. `index-authoring-sync.md` owns the authoring-time index →
frontmatter sync and the relay; it says nothing about projection direction. D36
in `index-composition.md` already owns both projections and the "One lookup
disambiguates a deletion" rule, so the new paragraph sits directly after it.

Verified against `scripts/lib/index-compose.sh`:

- The down projection builds three path lists — root's working tree, the
  carrier, and root at `HEAD` (`gitlore_compose_down`, 683-741; the `HEAD` list
  at 718-726 is `git show HEAD:MEMORY.md` filtered to the tier's prefix). The
  decision is at 742-752: root has it → root's bullet wins; root lacks it and
  `HEAD` lacks it → the carrier's bullet is kept; root lacks it and `HEAD` has
  it → dropped. So a path absent from root at `HEAD` survives a root-side
  deletion.
- A kept carrier-only line is reported by `gitlore_compose_orphans`
  (index-compose.sh:839-856) as
  `<carrier>: <path> is in the tier but not in the root index`. The skill and
  the node say "reported", not "written back" — I checked
  `gitlore_compose_root_bullets` (757-800): root's own lines are used whenever
  root carries any line for that tier, so the orphan is *not* hoisted back into
  root.
- Whether an arrived path is at `HEAD` depends on the bookkeeping commit.
  `gitlore_adopt_stage_pair_and_commit` (resolve.sh:2099-2120) stages the pair
  and calls `gitlore_commit_tier_bookkeeping` (2138-2176), which returns early
  with `… were staged rather than committed. They ride the next memory commit`
  when the store was dirty before the take, and otherwise commits the pair. A
  landed merge's compose write stays dirty for the next FR11 commit
  (`index-composition.md:128-131`). That is why the check is needed rather than
  assumed, and the paragraph says so.

**Procedure → `skills/merge/SKILL.md`, new `## Correcting what arrived`
section.** Two paragraphs: correct after propagating and never during, with the
"later is the next step, not permission to skip it" clause; and the two-edit
removal, closing on `git -C memory show HEAD:MEMORY.md` as the check to run
before assuming one pass suffices. The skill cites no memory file, no `plans/`
path and no private path. It is 107 lines, well under the ~200 cap, so no
`references/` file was needed.

One correction to the memory fact's wording: it gives the check as
`git show HEAD:memory/MEMORY.md`. The memory store is a submodule, so from the
parent that path is a gitlink and the command does not resolve the index; the
script runs `git -C "$mempath" show HEAD:MEMORY.md`. The skill uses
`git -C memory show HEAD:MEMORY.md`, matching `skills/push/SKILL.md:81`'s
`git -C memory` form.

## Checks run

- `just format-docs` → rc 0 (`Issues: Found 199 issues in 111/406 files`, the
  recipe's usual MD013 residue summary). It reflowed
  `docs/references/index-composition.md`; `skills/` is outside its scope
  (`rumdl fmt --no-cache docs plans`).
- `scripts/check-docs-links.py` → rc 0, `52 decisions, 121 files scanned`, all
  nine counters at 0 including `oversized-file`. This covers the new
  `[merge-and-resolve.md](merge-and-resolve.md)` link I added in D36.
- `scripts/run-bats.sh tests/plugin_distribution.bats` →
  **15 passed, 0 failed**. `tests/plugin_distribution.bats:153` is the only test
  file in `tests/` that names `skills/merge` or the docs I touched; it asserts
  the frontmatter `name:`, the absence of `commands/merge.md`,
  `[ -x scripts/merge-memory.sh ]` and the `git config gitlore.mergeCommand`
  line, none of which my edits touch.
- Byte-exactness of every quoted message: `grep -cF` against
  `scripts/lib/resolve.sh` — 1, 1, 1 and 4 respectively for the four strings
  above.

I did not run `just precommit`, `just lint`, `just test-unit` or
`just test-integration`, per the dispatch.

## Flagged, not acted on

The `memory` submodule shows as modified in the parent's `git status`
(` M memory`; inside it, ` M MEMORY.md` and ` M ddaanet`). The tree was clean at
the start of this session and I made no write under `memory/`. During the run
the harness also reported the primary working directory moving to
`/Users/david/code/gitlore/memory/ddaanet` and then to
`/Users/david/code/gitlore/memory`; I ignored both and kept every command
anchored at `/Users/david/code/gitlore`. This looks like a concurrent session or
a hook-driven compose rather than anything from this batch — worth checking
before the gating commit, since a canned memory commit would sweep it up.
