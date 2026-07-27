## Current task

The `Bash`-arm thread is closed — the transcript-corpus measurement, the
timing against this repo's real tree, and a live `sed -i` confirmation all
landed in `docs/design.md` D17, and the probe corrected a wording carried in
D17 and both post-hooks (`PostToolBatch` fires once per **tool batch**, one
assistant message's calls, not once per user turn; one turn fired it twice).

Two threads remain, neither started. The **memory proof pass**: items 9-16,
eight local memory files judged in presentation order on whether each fact
still earns its place or is already owned by `docs/design.md`/`CLAUDE.md`,
then a cross-cutting sweep. And the **open decisions** below, walked one at a
time in presentation order.

## Open decisions

- Compose has no way to record which base it merged, so the vanished-pointer
  drop stays undiagnosed. A green suite must not be read as closing this.
- `scripts/check-version.sh`: delete or upstream. `plugin-dev/release.just`
  already bumps, commits and pushes `marketplace.json` and synthesizes a
  missing entry, so a release cannot produce the drift it detects;
  `version-guard.sh` (wired at `.claude/settings.json:9`) blocks the
  hand-edit path. It guards a hole closed at both ends and costs a
  `just precommit` dependency. Its header comment still says "Run via
  `make check-version`" — stale either way.
- The `PostToolBatch` per-batch fact went into
  `ddaanet/reference_hook_input_schema.md` with **no index line of its own**,
  because the index is at 89% of budget and a compaction is pending. Leave it
  unroutable, or spend the bytes.
