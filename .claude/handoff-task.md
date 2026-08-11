## Current task

The memory hygiene sweep is planned in `plans/memory-hygiene-sweep.md` and ready to execute: Sweep A, a scripted drift/deictic/naming checker that becomes a `just precommit` gate once existing violations are cleared, then Sweep B, an ownership audit over the 99 ddaanet facts classifying each retire/relocate/keep without editing anything.

The `MEMORY.md` compaction fork — tier-wide retirement versus sub-scoping the tier mount — is deliberately parked until B reports, because B's retirement count is what decides it. A 5-file sample yielded one retirement candidate, extrapolating to ~20 against a budget needing ~25.

## Open decisions

- Whether to keep the five sample rewrites from the compaction experiment: `tier-routing-plugin-shaped`, `plan-length-matches-work`, `spec-contract-size-predicts-pr-size`, `ground-formulas-in-data`, `no-code-for-impossible-cases`. They net 212 bytes and move the index not at all, but they removed a direct naming of my human partner and a stale `reference_own_hooks_json_sandbox_erofs` reference. Keep as hygiene, or revert as noise.