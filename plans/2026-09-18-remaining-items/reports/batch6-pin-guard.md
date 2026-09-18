# Batch 6 — the pin guard's ahead-of-pin branch, and a silent abort

Two behaviour changes, both landed, uncommitted in the working tree.

## Item 1 — a tier merely ahead of its pin is put back on it for the take

### What I verified before building on it

`gitlore_adopt_advanced_live` (`scripts/lib/resolve.sh:1848`) fires on
`gitlore_live_ahead_of_head` — `HEAD != live` and `merge-base --is-ancestor HEAD
live` — then refuses a dirty store, checks the tier out at `live`, and calls
`gitlore_adopt_tier_into_root`, which composes the carrier up into the root index
and stages/commits the pair. So the state it takes is: clean tier, `HEAD` at the
pin, `live` ahead of it.

That is exactly the state the new branch produces. The guard's precondition
(`live` contains `HEAD`, `HEAD` strictly ahead of the pin) implies, after the
checkout to the pin, that `live != pin` and `pin` is an ancestor of `live` —
i.e. `gitlore_live_ahead_of_head` is true.

Its tests confirm the adoption end to end rather than just the ref move:
`tests/merge_memory.bats:516-556` (fixture `strand_live_ahead_of_pin`) asserts
HEAD adopts `live`, the memory store re-pins there, the carrier's line reaches
the root index, and the store is left clean; `tests/push_behind_vs_diverged.bats:268`
asserts the same from the publish preflight. `gitlore_merge_one_store` calls the
adoption right after its fetch, skipping it only when the fetched `origin/live`
already contains `live` — not our case, since `live` here holds local commits.

### Files changed

- `/Users/david/code/gitlore/scripts/lib/index-compose.sh` —
  `gitlore_compose_check_pins`' ahead-of-pin arm.
- `/Users/david/code/gitlore/scripts/lib/resolve.sh` — the commit path's abort
  wrapper carried a comment asserting that `/gitlore:merge` "sent the reader in a
  circle" for a tier ahead of its pin. That claim is now false for this branch,
  so it is replaced by the per-cause list the wrapper actually relies on. No
  behaviour change here.
- `/Users/david/code/gitlore/tests/index_compose.bats` — new fixture helper
  `move_tier_off_pin_into_live`, three new cases, one existing case rewritten.
- `/Users/david/code/gitlore/tests/commit_memory.bats` — the both-arms wording
  pin repointed at the new remaining-refusal text.
- `/Users/david/code/gitlore/docs/decisions.md`,
  `/Users/david/code/gitlore/docs/references/git-hooks.md`,
  `/Users/david/code/gitlore/docs/references/index-composition.md`.

### Behaviour

Inside the ahead arm (`pinned` an ancestor of `HEAD`), three outcomes:

1. **Clean tier whose local `live` contains `HEAD`** → `gitlore_git checkout -q
   --detach <pin>`, then a problem line saying the tier is back on the pin with
   nothing lost and naming `/gitlore:merge` as the next command. The refusal
   stands: the root index still has to take the carrier.
2. **The checkout fails** → the tier is untouched, git's own message is folded
   onto the one problem line (newlines squashed, one problem per line is this
   function's contract), with the `checkout --detach <pin>` command that finishes
   the return.
3. **Every other ahead tier** (dirty, no local `live`, `live` short of `HEAD` or
   diverged from it) → refusal, reworded. It no longer prescribes rebuilding
   root's block by hand; it names `/gitlore:merge` as the adopter, the ff-checked
   `git -C "<abs>" push . HEAD:refs/heads/live` that puts the commits where the
   take reads them (the same move `gitlore_repair_stranded_live` makes), leaving
   the tier clean, and `/gitlore:resolve` for a push refused as a
   non-fast-forward.

The mid-merge branch still runs first, so a tier that is both mid-merge and
ahead is unaffected.

### Design choices

- **The guard checks out, it does not adopt.** Adoption writes the root index and
  stages a gitlink; the guard runs from every compose (`SessionStart`,
  `PostToolBatch`, the commit path), where such a write would land work no
  approval covers in the next approved commit. The checkout is the one move that
  writes no index and needs no approval — it returns the tier to the commit the
  memory store's index already records, which is what `submodule update` would do
  at the next `SessionStart`. Recorded as a rejected alternative by name.
- **The refusal stands in case 1.** The carrier still has to be adopted up before
  anything composes down onto it, and the commit path must not proceed. The
  message carries the act (back on the pin) plus the next command.
- **One reworded text for the remaining ahead cases**, rather than one per
  sub-case: the two blockers (dirt, `live` short of `HEAD`) are stated as the
  conditions the take needs, and both acts are named. Branching the text per
  cause would re-derive a cause the reader can see in their own store.
- **Reported on both channels**: the guard's problems reach
  `gitlore_compose_and_report`'s `systemMessage` and `additionalContext`, so a
  `SessionStart`/`PostToolBatch` checkout is never silent.

### Red / mutation evidence

- `a tier ahead of its pin whose local 'live' holds its commits is returned to
  the pin for the take` — genuine RED against unchanged code at
  `tests/index_compose.bats:455`,
  `[ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pinned" ]` failed. Green after
  the branch landed.
- `a tier ahead of its pin whose commits HEAD alone holds is refused where it
  stands` and `a dirty tier ahead of its pin is refused where it stands` — the
  wording assertions were proven by a by-hand mutation of the message
  (`push . HEAD:refs/heads/live` → `push . HEAD:live`, `leave nothing uncommitted
  in` → `leave nothing dirty in`): both failed, on
  `[[ "$tierline" == *"git -C \"$abs\" push . HEAD:refs/heads/live"* ]]` (line
  406) and `[[ "$tierline" == *"leave nothing uncommitted"* ]]` (line 442)
  respectively. Mutation inverted by hand; `git diff scripts/lib/index-compose.sh`
  re-read afterwards and shows only the intended change. (`mutate-and-run.sh`
  refuses a subject with uncommitted edits, which this file had.)
- `a tier that cannot be returned to its pin is refused untouched, with git's own
  message` — proven by mutating the guard to ignore the checkout's status
  (`... 2>&1) || true; then`): failed on
  `[[ "$tierline" == *"could not be returned to the pin"* ]]`. Mutation reverted.
- `the pin-abort's ahead wording reaches both the agent arm and the user arm`
  (`tests/commit_memory.bats`) went red on `[[ "$agent_line" == *"discard"* ]]`
  when the message lost its "discard the commits" half — that is the wording pin
  doing its job; it now pins `leave nothing uncommitted`, which only the new text
  carries.

A note on one induction: `git checkout --detach` exits **0** after printing
`error: unable to unlink old '<file>': Permission denied` (measured, git 2.47),
so a `chmod a-w` induction moves HEAD and proves nothing. The failing-checkout
case therefore stubs `git` for that one call and leaves every other git call in
the pass alone; the reason is in the test's comment.

## Item 2 — the silent abort in the rc-1 case

`gitlore_sync_memory_to_live`'s rc-1 arm reads `git status --porcelain --
MEMORY.md` to decide whether a composition problem sits in a file this commit
changes. Both reads — root's index and each tier's carrier — aborted with
nothing printed. Both now report through one helper,
`gitlore_say_unreadable_index_status` (`scripts/lib/resolve.sh`, defined after
its user), which emits on both channels: the compose refusal that sent the run
to the read, the index whose status could not be read, that the commit was
aborted, that the approved summary is still in place (the caller restamps), and
the next command.

Those are the only two arms of that case that were silent; the `abort_files`,
`went ahead`, rc-2 and unknown-status arms all report already.

### Red evidence

- `a tier whose index status cannot be read aborts the commit and restamps the
  approval` — extended, RED at `tests/commit_memory.bats:296` on
  `[[ "$stderr" == *"could not read the status of memory/ddaanet/MEMORY.md"* ]]`.
- `a root index whose status cannot be read aborts the commit and says which
  index` — new, for the sibling arm. Green from birth (the helper was in by
  then), so proven by removing the root arm's call: failed on
  `[[ "$stderr" == *"could not read the status of memory/MEMORY.md"* ]]`. Call
  restored. Its stub matches the `-- MEMORY.md` pathspec form only, so the bare
  `git -C memory status --porcelain` in `gitlore_memory_dirty` earlier in the run
  still goes through.

## Suites run (foreground, one at a time)

All green, no failures anywhere:

| suite | count | | suite | count |
| --- | --- | --- | --- | --- |
| index_compose | 88 | | resolve_merge_local | 4 |
| commit_memory | 38 | | resolve_merge_remote | 3 |
| git_hook_pre_commit | 21 | | resolve_merge_briefing | 8 |
| git_hook_memory_pre_commit | 3 | | merge_commit_hygiene | 10 |
| resolve_compose | 26 | | index_merge | 20 |
| resolve_recovery | 23 | | index_sync | 87 |
| tier_divergence | 20 | | bsd_portability | 3 |
| merge_memory | 42 | | push_rejection_discriminator | 9 |
| tier_lockstep | 14 | | integration_gitlink_staging | 4 |
| push_behind_vs_diverged | 21 | | integration_happy_path | 1 |
| cc_hook_index_compose | 28 | | integration_memory_gate | 2 |
| cc_hook_add_tier | 12 | | integration_replay_guard | 7 |
| cc_hook_session_start | 25 | | emit_memory_gate | 7 |
| resolve | 8 | | cc_hook_post_tool_use | 11 |
| resolve_both_flavors | 4 | | plugin_distribution | 15 |
| lint_shell | 3 | | check_docs_links | 43 |

That is every suite that reaches `scripts/lib/index-compose.sh` or
`scripts/lib/resolve.sh` through a compose, a commit path, a take, a push, a
resolve or a hook, plus the three the task named. Not run, as touching neither
script's behaviour: `emit_wrappers`, `emit_launcher`, `global_shim`,
`hook_manager_*`, `install_run`, `write_settings`, `memory_hygiene`-style
authoring suites, and the `evals` recipe.

`just format-docs` rewrapped one file (`docs/references/index-composition.md`);
`python3 scripts/check-docs-links.py` reports 54 decisions, 121 files, zero
findings on all nine checks.

## Docs

- `docs/decisions.md` — D50's conclusion line gains "a tier merely ahead of its
  pin is put back on it for `/gitlore:merge` to adopt"; the Git-hooks group's
  *Rejected* line gains **a blanket refusal for every tier ahead of its pin** and
  **adopting inside the pin guard rather than directing to `/gitlore:merge`**.
- `docs/references/git-hooks.md` (the node that owns the pin guard, under D50) —
  a new paragraph with the mechanism: what the checkout leaves, why the refusal
  stands, the two states left alone and their remedies, and the failing checkout.
  Both rejected alternatives argued by name in the node's own section.
- `docs/references/index-composition.md` — one sentence in the rule-7 summary
  pointing at the node, alongside the existing mid-merge sentence.

Nothing under `skills/`, `commands/` or `agents/` quotes the superseded wording
(grepped for `no automatic remedy`, `replace every line`, `stage the gitlink`,
`ahead of the pin`); the only occurrence was the message itself.

## Not done, with reasons

- **No changelog entry.** `docs/changelog.md` plus `docs/changelog/<date>-…md` is
  the venue for a behaviour record, and this change would warrant one, but the
  task named `decisions.md` and the mechanism node only, and a concurrent batch
  is editing docs records — a second writer in `changelog.md` risks a conflicting
  edit. Flagging it rather than taking it.
- **No spaced-path case for the new branch.** The messages quote `"$abs"` and
  every git call quotes its path, and `commit_memory` already carries spaced-root
  coverage for the commit path, but no new test exercises a tier path holding a
  space through the checkout branch.
- **Residual, stated rather than fixed:** after the guard returns a tier to its
  pin, a retry that does *not* run `/gitlore:merge` first will compose and commit
  normally (the tier is on its pin, nothing refuses) with the commits still held
  in `live`; a later tier commit would then meet a non-fast-forward `HEAD:live`
  push from `gitlore_sync_tiers_to_live`. Nothing is lost in either case, and the
  message names the take as the next command.
