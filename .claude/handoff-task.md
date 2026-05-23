## Current task

Decide whether to investigate the broken `autoMemoryDirectory` redirect (memories silently strand in CC's default dir instead of the submodule) before resuming Plan 04 Steps 4–7 (push `ddaanet/gitlore`, marketplace entry, outer-loop dogfood, document install).

## Open decisions

- Investigate the `autoMemoryDirectory` redirect now vs. proceed to Plan 04 with manual live→submodule sync as a known workaround. This session found the setting stably present yet not honored — the existing "effective next session" theory doesn't explain it, and memory goes stale every session without a hand-sync. Recommended: investigate first, since it silently corrupts the product's core promise.
- Plan 04's push must precede any live verification of this session's approval-gate hardening — sub-agents dispatch from the installed plugin cache, so the hardened `memory-merger`/hook prose can't be dogfooded until pushed + reinstalled.
