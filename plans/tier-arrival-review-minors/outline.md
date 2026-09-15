# Outline: tier-arrival review minors

This job fixes the 21 Minor findings of
`plans/unadoptable-tier-arrival/reports/deliverable-review.md`, over the tree
that the `unadoptable-tier-arrival` job left. Item numbers are this job's own,
as `classification.md` numbers them.

`plans/unadoptable-tier-arrival/dispatch-constraints.md` binds every dispatch,
with one exception. `.claude/handoff-task.md` and `.claude/handoff-todo.md` are
folded into this job's commits, and are not left unstaged.

## Scope

IN:
- all 21 Minor findings.

OUT:
- The Major, the merge skill's unconditional `/gitlore:push` claim. It is
  tracked in `.claude/handoff-todo.md`.
- The review's tracked exclusions:
  - the rootless store;
  - the batch-retry approval gap;
  - the untested restamp, mode and CRLF arms;
  - the never-published memory push;
  - the bound on refuse/re-synthesize cycles;
  - the 400-line cap on the scripts.
- Splitting `index-compose.sh` or `lib/resolve.sh`.

## Phase 1: repair and walk-back messages (tdd), items 1, 2, 3, 7

The changes are in `gitlore_adopt_tier_into_root` and the repair helpers below
it, in `scripts/lib/resolve.sh`.

`gitlore_adopt_repair_arrival` gains a new last argument: the refusal's full
problem list, `$composed`. The carrier problems stay the condition the caller
tests.

**Unrepairable arm (item 1).**
- The carrier lines keep their `live:MEMORY.md:` form and their header.
- Every refusal line that does not name the carrier follows, under
  `gitlore: the root index could not take tier '<t>''s lines:`. Each gets a
  `gitlore:   ` prefix, the format the walk-back arm already uses.
- When such lines exist, the remedy names both fixes: fix the listed problems in
  this repo, and run `/gitlore:merge` once the index is fixed where it was
  published.
- Otherwise the remedy is unchanged.

**Transient arms (item 2).** The arms are:
- `mktemp`;
- the arrival read;
- the pin read;
- the rewrite;
- the commit build;
- the `push . R:live` advance;
- the `checkout --detach live` follow.

Each prints the full refusal under that header. It then walks back with the
remedy `Run /gitlore:merge again.`, because the next take repairs from scratch.
The `mktemp` arm prints nothing today; it gains its own `could not …` line, in
the shape of its siblings.

**Walk-back wording (item 3).**
- `gitlore_adopt_walk_back_tier` takes what `live` holds as a parameter.
  `gitlore_adopt_report_refusal_and_walk_back` passes it through.
- The default is `what arrived`.
- The retry-refusal arm and the checkout-follow arm pass `the repair`, because
  in both `live` already holds R.
- Every other caller keeps the default.

**Scratch directory (item 7).**
- The scratch directory moves from the tier gitdir to
  `mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"`. This is the idiom of
  `scripts/resolve.sh`'s merge message file.
- A killed take then leaves nothing in a repo, and there is no library-level
  `trap` to clobber the caller's.
- Nothing needs the scratch copy inside the gitdir:
  - `gitlore_repair_index` renames within the scratch directory's own directory;
  - `hash-object -w` writes to the tier's object store whatever the path;
  - `GIT_INDEX_FILE` can point anywhere.
- Update the function comment's "inside the tier's gitdir" clause.
- *Rejected:* sweeping stale `gitlore-repair.*` directories on the next repair.
  It races a concurrent take.

**Tests** (`tests/merge_memory.bats`, beside the repair cases at 558–812):
1. **Mixed refusal.** An unrepairable arrival plus a root duplicate:
   - both problem sets are printed;
   - the remedy names both fixes.
2. **Transient failure.** Break the commit build with a `git` stub that fails
   `commit-tree`. This fails identically before and after the scratch move.
   - The refusal is printed, followed by `Run /gitlore:merge again.`
   - `Fix the store` is never printed.
3. **Retry refused on root.**
   - The output prints `keeps the repair`.
   - It never prints `keeps what arrived`.
4. **Scratch location, observed mid-repair** (`rm -rf` hides it afterwards).
   - A `git` stub on `PATH` forwards to the real git.
   - On `commit-tree`, the stub records
     `ls -d "$gitdir"/gitlore-repair.* "$TMPDIR"/gitlore-repair.*` to a file.
   - Assert the tier gitdir had no entry, and `$TMPDIR` had one.
   - Today's code fails the first assertion.
5. **Existing test.** Rewrite `merge_memory.bats:771` to the new wording.

## Phase 2: push publication (tdd), items 4, 5

The changes are in `gitlore_push_stores`, in `scripts/lib/resolve.sh`.

**Item 5, the race (Defect): reproduce first.** Two places in the tier loop run
the take pass over every store mid-loop:
- the `behind` arm (`:1394`);
- the `live`-ahead-of-HEAD take (`:1366`).

Either can fetch and repair a tier whose own iteration already pushed. Memory's
push then records a gitlink that tier's remote lacks.

*Fixture:*
1. Create tiers `a` and `b`, in `.gitmodules` order.
2. `a` is ahead and pushes.
3. A `post-receive` hook on `a`'s bare remote then runs `update-ref` to move its
   `live` onto a commit whose `MEMORY.md` carries a duplicate pointer.
4. Run two variants, each RED on its own:
   - `b` behind;
   - `b`'s `live` ahead of HEAD.

*Expected RED:* memory's push records `a`'s gitlink at R, and `a`'s remote lacks
R. If neither variant reproduces, the phase stops and reports. Nothing is fixed
on reasoning alone.

*Fix:*
- Drop the in-arm retry push.
- After the tier loop, and before memory's fetch and push, one pass over
  `gitlore_tier_paths` pushes every tier whose `live` is not an ancestor of
  `origin/live`. This covers the current tier, as the retry did, and any tier
  that either mid-loop take repaired.
- The pass skips a tier with no local `live`, the loop's own condition
  (`:1341`).
- A tier with no remote never reaches the pass, because the loop has already
  returned 1.
- A missing `origin/live` fails the ancestry check, so the tier is pushed.
- A refusal in the pass is reported and returns 1. The pass never loops.

**Item 4, error wording and duplication.**
- Extract one reporter for a tier push failure. It classifies git's error:
  - A divergence reason (`fetch first` / `non-fast-forward`) gets the existing
    "refused as a non-fast-forward … the remote moved during the push" wording.
  - Anything else gets "not because of divergence".
- The new pass and the outer `*)` arm call it.
- The outer `case` arms that already classify keep their own branches.

**Tests** (`tests/push_behind_vs_diverged.bats`):
- the two race variants above;
- a push in the pass that is refused as non-fast-forward. It gets the
  moved-remote wording, never "not because of divergence";
- the existing 338/376/404 cases, which still pass unchanged.

## Phase 3: byte preservation (tdd), item 6

**Rule** (`gitlore_repair_index`, `scripts/lib/index-compose.sh`): a line keeps
its own terminator. The output stays unterminated only when its last element is
the input's last line, or that line's tail after a weld split. A line that stops
being last gains exactly one newline.

**Two cases break the rule today:**
1. The dropped duplicate was the unterminated last line. The survivor before it
   loses its newline.
2. Strays moved out of the pointer block land after the last bullet. When that
   bullet is the unterminated last line, the last moved stray loses its newline.

**Fix:** decide termination by the provenance of the output's last element, not
by the input's terminated state alone. The executor chooses how to track that
provenance across the split, move and drop stages. The weld split already keeps
the tail last.

**Tests** (the repair section of `tests/index_compose.bats`). Each fixture is
unterminated, and each asserts byte equality: the named lines are removed or
moved, every other line keeps its bytes, and a line that stopped being last
gains exactly one newline.
1. Case 1 above.
2. Case 2 above.
3. An unterminated file whose last line survives in place stays unterminated.
   Confirm existing coverage, and add this case only if it is missing.

## Phase 4: continuation pre-landing exits (tdd, then prose), item 15

**Harness** (`scripts/resolve.sh:310-315`). The new lines are descriptive only,
with no directive:
- A failed message build prints
  `gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared.`
  before `exit 1`.
- A refused merge commit prints
  `gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared.`
  after git's own reason.
- Both share the phrase `the merge was not committed` with the merged-index
  gate's line.

**Prose.**
- `agents/memory-merger.md:39`: any line with `the merge was not committed`
  means the merge is unlanded.
  - The merged-index line keeps its current handling: quote the problem lines,
    stop, and wait for `rejected:`.
  - The build or commit line: quote it together with git's reason above it, say
    the merge is unlanded, and stop.
  - The "otherwise" branch stays post-landing.
- `skills/resolve/SKILL.md:83-86` makes the same split.
  - A merged-index refusal is re-synthesized.
  - A build or commit refusal is relayed with git's reason: the merge stays
    prepared, and the remedy is to fix that reason and rerun `/gitlore:resolve`.
    There is no rejection cycle.

**Residual:** a staging failure inside `compose_merged_indexes` aborts under
`errexit` with git's own text and no `gitlore:` line. The comment at
`scripts/resolve.sh:105-109` states it as the bound, because wrapping the call
would suspend `errexit` across the function.

**Tests** (`tests/resolve_compose.bats`):
- A merge commit refused by a failing hook in the store, via a fixture-set
  `core.hooksPath`:
  - it prints the line and exits 1;
  - `MERGE_HEAD` is kept;
  - no message file is left in `$TMPDIR`.
- A message-build failure gets the same assertions, if a fixture can make
  `gitlore_merge_commit_message` fail. Otherwise the executor states why the
  case is untested.

## Phase 5: test specificity (general, test-only), items 9–13

No production code changes. Each new assertion must fail against a named mutant
in place of a RED phase: the executor applies it briefly, observes the failure,
reverts, and reports the failing output.

- **Item 9** (`index_compose.bats:1143`): drop `(K3)` from the section header.
- **Item 10** (`index_compose.bats:1105-1127`):
  - Add a decoy `memory/org/memory/MEMORY.md: …` line to the attribution
    fixture.
  - Query root `memory/MEMORY.md` and assert the decoy is excluded.
  - *Mutant:* an unanchored `grep -F` replacing the `case` prefix match.
- **Item 11** (`merge_memory.bats:744-778`, as Phase 1 leaves it):
  - Assert no output line starts with `gitlore:   <tierpath>/MEMORY.md:`.
    *Mutant:* the unrepairable arm prints `$line` unstripped.
  - Assert memory `HEAD` is unchanged across the take. *Mutant:* the
    unrepairable arm falls through to `gitlore_adopt_stage_pair_and_commit`
    instead of walking back.
- **Item 12:**
  - A root weld abort through `scripts/git-hooks/pre-commit`
    (`git_hook_pre_commit.bats`), asserting the abort and the approval restamp.
    *Mutants:* the rc 1 arm treats a dirty root index as advisory; the arm skips
    the restamp.
  - The pre-commit carrier test gains a `live` pin, and asserts the hook's exact
    exit status for this abort instead of `-ne 0`. *Mutant:* the rc 1 arm treats
    a dirty carrier as advisory, which the missing pin's guard refusal would
    otherwise mask.
- **Item 13:** three tests, each over its tested sibling rule's fixture:
  - Rule 4 (interleaved line) on the dirty-file abort (`commit_memory.bats`).
    *Mutant:* `gitlore_compose_check_index` skips rule 4.
  - Rule 2 on the advisory arm (`commit_memory.bats`). *Mutant:* the advisory
    arm prints only file-prefixed lines, dropping rule 2's prefixless ones.
  - Rule 4 on the merged-root gate (`resolve_compose.bats`). *Mutant:*
    `gitlore_compose_check_index` skips rule 4.

## Phase 6: comments and docs (inline), items 8, 14, 16–21

- **Item 8** (`index-compose.sh:268-270`): replace "no take can walk back from"
  with "no take can adopt past".
- **Item 14** (`agents/memory-merger.md` step 6): add "no two bullets naming the
  same path" to the index rules.
- **Item 16** (`git-hooks.md:155-157`): "A duplicate, interleaved or welded line
  in an index file with uncommitted changes — root's `MEMORY.md` or a tier
  carrier — aborts".
- **Item 17** (`tier-arrival-repair.md:20-26`): frame the wedge as the
  unrepaired case: "Left unrepaired, every later take …".
- **Item 18** (`tier-stores.md:190-195`): replace "The remedy is printed
  instead" with "It prints the remedy — …".
- **Item 19:** count the siblings listed in `tiered-memory.md:30-45`.
  - Make `index-authoring-sync.md:5` ("four nodes") and `tiered-memory.md:5`
    ("four sibling nodes") state that count.
  - Grep the other nodes for the same phrase.
- **Item 20** (`docs/changelog.md:15-16` and the entry file's matching line):
  replace "refused for any other reason" with "refused for any reason but
  divergence".
- **Item 21** (`commit-gate.md:57-61`): "A refusal that needs the agent to act
  lands only once it is done: an edit, for a problem in an index file the commit
  changes (D50…), or a checkout or take, for an off-pin tier."
- **D52 node mechanism changes** (`tier-arrival-repair.md`):
  - `:34-35`: the scratch copy lives under `$TMPDIR`.
  - `:92-98`: a take's repair is published by the post-loop push pass, which
    also covers a tier that a later iteration's take repaired.
  - The repair's transient arms say `Run /gitlore:merge again.`
  - The walk-back names what `live` holds.
  - Grep `docs/design.md`, `docs/decisions.md` and `tier-stores.md` for the same
    claims.
- **Messages changed in Phases 1, 2 and 4:** grep `docs/references/` and
  `skills/` for each changed string, and update every quote.
- **Changelog:** one entry file plus its index line for this job.

## Dependencies

- Phases 1–4 touch disjoint functions and run sequentially in the main tree.
- Phase 5 runs after Phase 1, whose rewrite item 11 edits, and after Phase 4,
  since both add to `resolve_compose.bats`.
- Phase 6's sweep of quoted messages and mechanisms runs last, once every string
  and mechanism is final.
- `just precommit` runs at the end of each phase, in the background.

## Open questions

None. Both choices the outline took were confirmed at proof:
- The scratch directory lives under `$TMPDIR`. *Rejected:* a stale-directory
  sweep, which races a concurrent take.
- Item 15 gets descriptive harness lines that the prose keys on. *Rejected:* a
  prose-only fix, which would have the merger inspect `MERGE_HEAD` itself.
