## Current task

The `/gitlore:push` behind-vs-diverged defect is **fixed and verified, uncommitted**.
The brief is `plans/brief-push-misreads-behind-as-diverged.md`; every claim in it
reproduced against a real remote before any code changed.

What landed, all in `scripts/lib/resolve.sh` unless noted:

- `gitlore_classify_refusal` — ancestry, not git's wording, decides a refused
  push: `behind` / `diverged` / `ahead` / `unknown`. Wired into all FOUR sites
  that classified on the parenthesized reason, not the two the brief named:
  both remote pushes (tier loop, memory) and both local `push . HEAD:live`
  sites (`gitlore_sync_tiers_to_live`, `gitlore_sync_memory_to_live`).
- `gitlore_check_head_live_agree` — refuses to publish a store whose HEAD and
  local `live` name different commits, naming both shas and the remedy for the
  direction found. Reports, never repairs.
- `gitlore_prepare_merge` — ancestry test before the `checkout --detach`, plus
  a restore of the prior HEAD if it reaches the no-`MERGE_HEAD` path anyway.
- `scripts/push-memory.sh` — credits only a remote tip the store's own `live`
  contains, so a remote someone else advanced is no longer reported as commits
  this run published; a store held back that way suppresses the closing
  "already up to date" line.
- `tests/push_behind_vs_diverged.bats` — 8 cases, each watched red first.
  `tests/resolve_recovery.bats` updated: same intent and assertions, new
  message, plus the HEAD-unchanged assertion that is the point of the change.
- `docs/changelog/2026-08-12-behind-is-not-diverged.md` + index line;
  `docs/design.md` states the ancestry discriminator and the HEAD==live
  precondition.
- `memory/ddaanet/git-stderr-and-parsing.md` corrected — it had asserted
  `(fetch first)`/`(non-fast-forward)` = divergence, which is the imprecision
  that caused this bug.

Verification: `GITLORE_GATE_FORCE=1 just precommit` — 614 unit + 72 integration
passing, lint clean, version in sync. The force flag was needed because an
earlier run wrote a sentinel while its suite executed against a mid-flight tree.

## Open decisions

- Does the memory-hygiene checker ship as part of gitlore, or stay a
  `scripts/` local? It works and blocks in `just precommit` now, so the
  deferral has expired. Shipping makes python3 + PyYAML a user-facing
  dependency, which is why `scripts/hook-manager/wire-*.sh` probes for
  `python3 -c 'import yaml'` rather than assuming it.
- Compacting `memory/MEMORY.md` is forcing, no longer deferred. The index is
  now ~24709 bytes against Claude Code's ~24985-byte loader cutoff — this
  session's correction to the git-stderr line spent ~37 of the remaining
  bytes. Past the cutoff the tail never reaches a session, and composition
  puts this repo's own project lines in that tail. Sweep B's retirement
  verdicts are the only lever that frees bytes without weakening a trigger.