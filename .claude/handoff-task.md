## Current task

Next is `/design` on **the unadoptable tier arrival**, deliverable-review Major 1 of `plans/index-edit-propagation/reports/deliverable-review.md`. My human partner chose C plus prevention through the `/ddaa:proof` pass, and rejected A (a message fix alone) and B (a push that no longer fails on it) as punting.

**The defect.** `gitlore_compose_up` runs `gitlore_compose_check` over root and every carrier, so an arriving carrier with a duplicate pointer, a stray line or a welded line is refused.
- `gitlore_adopt_tier_into_root`'s walk-back (`scripts/lib/resolve.sh`) puts the tier back on its pin. The defect now lives only in the tier's `live`, yet the message names the clean worktree file and says "Fix the store".
- `gitlore_push_stores` retakes whenever `live` is ahead and returns 1, so every `/gitlore:push` and parent `git push` fails.
- No local remedy exists. The take refuses a dirty tier, checking the tier out at `live` is what the pin guard refuses, and a hand commit on `live` bypasses the approval gate.
- `rest_unadopted_tier` in `scripts/resolve.sh` leaves the same shape.

**How upstream publishes it.** On the commit path a `gitlore_compose_check` refusal is rc 1, which reports and continues (`gitlore_sync_memory_to_live`). `gitlore_sync_tiers_to_live` then commits the defective carrier and `pre-push` publishes it. The upstream agent sees an advisory refusal on its next compose and nobody learns a downstream is blocked. Writers outside gitlore have no process at all: a hand push, an older gitlore, an append outside the hooks.

**The design to produce:**
1. **Downstream repair (C).** A take whose compose refusal names the arriving carrier prepares the arrival as a repair merge instead of walking back. The memory-merger gets the problem list, the continuation composes up and adopts, and the repair publishes to every consumer. The tier-merge-direction rule ("correct content after propagating, never during") governs wording. A structural defect the up projection cannot adopt is a different case, and the D50 node should record that distinction.
2. **Upstream prevention.** The commit path aborts (rc 2 shape, approval kept) when a refusal names the carrier of a tier being committed. A root-only problem stays advisory, because it never leaves the repo. This contradicts the current rc 1 comment.
3. **Fold in minor-pass-2's code m4.** `push_or_report` exits before `rest_unadopted_tier`. The recommendation is a distinct status, resting the tier after an origin-push failure and keeping it on the merge after a local `HEAD:live` failure. See `plans/index-edit-propagation/reports/minor-pass-2.md`.

**Running in the background: Majors 2–5.** An opus agent is applying them and must not be re-dispatched. Its report is `plans/index-edit-propagation/reports/major-pass-2.md`; check that file and the tree first.
- Majors 2–5 are the `git-hooks.md` step numbers, the reverse empty-session drain half, the marker tests keyed to `test-session`, and the bare `compose_merged_indexes` call with its lock test in `tests/resolve_compose.bats`.
- The agent does not commit or run precommit.
- When it lands, review the red evidence in its report. Then the main session runs `just precommit` in the background and commits the Majors together with the uncommitted Minor pass (verified: lint clean, 19 bats files, 413/413), the review reports, `minor-pass-2.md`, `major-pass-2.md` and the handoff files.
