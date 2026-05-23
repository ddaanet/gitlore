## Current task

Verify the gitlore two-turn approval handshake via a live `/gitlore:resolve` dogfood, then execute Plan 04 Steps 4–7 (push `ddaanet/gitlore`, add marketplace entry, outer-loop dogfood, document install pathway).

## Open decisions

- How to verify the two-turn handshake before pushing: run a live `/gitlore:resolve` dogfood now against a manufactured divergence (this session already has the committed `gitlore:memory-merger` loaded, so it's verifiable here) vs. defer to the Step 6 outer-loop dogfood after pushing. User leaned "re-dogfood first, then push." The handshake is prompt-only and not bats-testable — a real-skill run is the only faithful check.
- Whether to commit the now-complete `docs/references/evals-best-practices.md` (uncommitted) before resuming Plan 04, or fold it into a later commit.
- GitHub-side cleanup of leftover dogfood remotes (`ddaanet/gitlore-dogfood-*`): fold into the Plan-02 leftover cleanup or leave to the user.
