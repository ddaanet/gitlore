## Open decisions

- Whether `tests/mutate_and_run.bats:83` should assert with `assert_fails "selected no test"` rather than the raw `[[ "$output" == *"selected no test"* ]]`. It failed once inside a cold 96-suite `--jobs 2` run and did not reproduce under a forced cold re-run, so it is a flake under load; the raw form makes bats print the failing line and not `$output`, so the nested suite's log is gone and the next occurrence is undiagnosable.

## Remaining

- Re-run `scripts/test-macos.sh` on a Mac to verify the four fixes. Cases 678–1016 have now executed there once; the 50 failures that run reported are diagnosed and patched, and the patches themselves are unverified on the platform.
- `/deliverable-review plans/batch-retry-approval-freshness` in a fresh opus session.
- Triage `inbox/brief-add-tier-index-budget-advisory.md`, `inbox/brief-index-audit-preamble-and-merge-unlanded.md`, `inbox/brief-session-start-protocol-context-wording.md` and `plans/brief-codex-native-memory-integration.md`, once the rest of the list is cleared; each brief's recommendation is input, and the choice is my human partner's.
- Continue the ddaanet review pass from `plans/ddaanet-memory-review.md` (entry 6, `hook-input-schema`).
