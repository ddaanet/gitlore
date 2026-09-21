## Remaining

- Run `scripts/test-macos.sh` on a Mac and patch what it turns up; the narrowed PATH has never met the full unit suite, and a missing tool (PyYAML for the hook-manager wiring suite is the likely one) goes through `EXTRA_TOOLS` or a fix. A `macos-latest` GitHub Actions job is free on this public repo and deliberately not set up yet.
- Close the batch-retry approval gap: on the PostToolBatch path the retry reuses the preserved summary, so the edit fixing an aborting index commits under the old approval although the abort text says the summary needs approval again; needs a status protocol between `commit-memory.sh` and the batch hook, designed before it is coded.
- Convert the suite's non-final `[[ ]]` assertions, or state why not: under bash 3.2 they pass silently while `[ ]` and plain commands fail the test, so only a modern-bash bats run checks them on a Mac (`tests/bsd_portability.bats` header, `docs/references/testing.md`).
- Retire the ddaanet fact `hook-output-channels` once `plugin-craft:hook-authoring` states that `systemMessage` renders ANSI; its pointer to `_wipe-emit.sh` names a file tracked nowhere.
- Triage `inbox/brief-add-tier-index-budget-advisory.md`, `inbox/brief-index-audit-preamble-and-merge-unlanded.md`, `inbox/brief-session-start-protocol-context-wording.md` and `plans/brief-codex-native-memory-integration.md`, once the rest of the list is cleared; each brief's recommendation is input, and the choice is my human partner's.
- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of native-recall attachments exist.
- Continue the ddaanet review pass from `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).
