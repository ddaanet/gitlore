## Current task

Working through the Critical and Major findings of the `plans/index-edit-propagation` deliverable review (`plans/index-edit-propagation/reports/deliverable-review.md`). C1 (with M4) and the take-path half of M5 have landed. Next is M5's other half, which my human partner agreed to as a separate commit with its own failing test first. `docs/references/git-hooks.md` D50's "compose up and stage the pair, or stage nothing" wording stays untouched until it lands.

The defect: in `scripts/resolve.sh` `continue-after-merge`, `compose_merged_indexes` only reports a failed `gitlore_compose_up` for a tier merge. The continuation then stages the moved tier gitlink and calls `gitlore_commit_tier_bookkeeping` anyway. That is the same silent overwrite the take path had, and no test covers a continuation compose refusal.

Proposed shape, presented to my human partner but not explicitly confirmed. It mirrors the take fix in `gitlore_adopt_tier_into_root` (`scripts/lib/resolve.sh`):
- Still land the merge: merge commit, clearing the merge state, `push . HEAD:live`, and any publish.
- Skip the gitlink staging and the bookkeeping commit.
- On the exit-0 paths only, check the tier out at the index pin `:$merged_tier`, and only when that pin is an ancestor of the merge commit. The store then matches the take fix's resting state (HEAD on pin, `live` ahead), which `gitlore_adopt_advanced_live` adopts on the next take.
- Leave the yield paths alone: the merge commit is only at HEAD there.

Still to settle while writing it: the exit status (the merge itself landed), and the remedy text, which today says to edit MEMORY.md, a remedy that is wrong once the pin is staged. Covering tests go in `tests/merge_memory.bats` or near the continuation cases. Code, tests and docs go in one commit (`docs/references/tier-stores.md`'s staged-pair paragraph names the continuation, plus a changelog entry).