## Remaining

- Re-run `scripts/test-macos.sh` on a Mac: cases 678–1016 have never executed there, and the first run's failures are patched, so the tail is the unknown. A `macos-latest` GitHub Actions job is free on this public repo and deliberately not set up yet.
- `/deliverable-review plans/batch-retry-approval-freshness` in a fresh opus session.
- Three pre-existing defects the phase-1 corrector flagged and left: after the landed-then-failed merge arm, the next batch's absent/blank screen in `memory-commit-batch.sh` asks for summary approval ahead of the sync's stale-merge guard, in front of a merge `/gitlore:resolve` owns; the hook's clean-memory branch says both IPC files are gone when it removes only the trigger; the blank-approval predicate is duplicated in `commit-memory.sh` and the hook and wants a `gitlore_approval_present` in `scripts/lib/util.sh`.
- Triage `inbox/brief-add-tier-index-budget-advisory.md`, `inbox/brief-index-audit-preamble-and-merge-unlanded.md`, `inbox/brief-session-start-protocol-context-wording.md` and `plans/brief-codex-native-memory-integration.md`, once the rest of the list is cleared; each brief's recommendation is input, and the choice is my human partner's.
- Continue the ddaanet review pass from `plans/ddaanet-memory-review.md` (entry 6, `hook-input-schema`).
