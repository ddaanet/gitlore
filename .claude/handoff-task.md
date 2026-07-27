## Current task

Two threads. The **memory proof pass** is the main one — items 9-16, eight local
files judged in presentation order on whether each fact still earns its place or
is already owned by `docs/design.md`/`CLAUDE.md`; then the cross-cutting sweep
(normalize `name:` frontmatter to the filename stem, re-audit dangling `[[...]]`
links store-wide). Separately, the `Bash` arm of the `PreToolUse` index trigger
is still proven only by the bats suite: `hooks.json` event registration freezes
at session start, so the widened `Write|Edit|Bash` matcher needs a fresh session
and a `sed -i` on the real `memory/MEMORY.md` to confirm that propagation and
composition both run.

## Open decisions

- `add-tier-batch.sh` drops the compose stamp assuming `PostToolBatch` hooks run
  in the order `hooks.json` lists them. Noise-suppression only — a wrong
  assumption costs one redundant idempotent compose — but it is unverified and
  the wrong answer is invisible, so it will never surface on its own.
- The `PreToolUse` pre-hook runs on **every** `Bash` call (cd to project root,
  two git queries, a `cp` of the index, a `cksum`). Cheap per call, new cost on
  the hottest tool, nothing measures it. Worth settling only after the dogfood
  decides whether `Bash` needs to be a trigger at all.
- Compose has no way to record which base it merged, so the vanished-pointer
  drop stays undiagnosed. A green suite must not be read as closing this.
- `scripts/check-version.sh`: delete or upstream. `plugin-dev/release.just`
  already bumps, commits and pushes `marketplace.json` and synthesizes a missing
  entry, so a release cannot produce the drift it detects; `version-guard.sh`
  (wired at `.claude/settings.json:9`) blocks the hand-edit path. It guards a
  hole closed at both ends and costs a `just precommit` dependency. Its header
  comment still says "Run via `make check-version`" — stale either way.
