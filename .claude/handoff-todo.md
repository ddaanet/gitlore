## Open decisions

- Whether `tests/mutate_and_run.bats:83` should assert in a form that prints `$output`, rather than the raw `[[ "$output" == *"selected no test"* ]]`. It has now failed twice inside a cold 96-suite `--jobs 2` run and passed in isolation both times; the raw form makes bats print only the failing line, so the nested suite's log is gone and two occurrences have bought no diagnosis. Siblings at lines 71, 77 and 93 share the form.
- Whether `inbox/brief-add-tier-index-budget-advisory.md` and `inbox/brief-index-audit-preamble-and-merge-unlanded.md` go now that their findings are fixed, as the inbox README's triage convention implies, or stay as the record of what was asked.

## Remaining

- Correct `skills/memory-writing/SKILL.md` §4: the recall cap is measured against the file, but the `description:` frontmatter is synced from the index line and so spends those bytes twice. §4 tells the reader to `wc -c` before adding a section without saying the line they must not trim is itself eating the budget — a 577-character index line costs a fact about 700 of its 4096 bytes before a word of body.
- Re-run `scripts/test-macos.sh` on a Mac to verify the four fixes. Cases 678–1016 have executed there once; the 50 failures that run reported are diagnosed and patched, and the patches are unverified on the platform.
- `/deliverable-review plans/batch-retry-approval-freshness` in a fresh opus session.