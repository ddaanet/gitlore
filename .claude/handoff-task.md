## Current task

Two threads. **Walking the open decisions one at a time**, in presentation
order: decision 1 (`add-tier-batch.sh` compose-stamp ordering) is closed —
all orderings compose correctly, only true concurrency costs one duplicate
message — and decision 2 (the `PreToolUse` `Bash` arm) is settled by a
transcript-corpus scrape, leaving the `check-version.sh` and compose-base
decisions below still to present. Separately, the **memory proof pass** has
not started: items 9-16, eight local files judged in presentation order on
whether each fact still earns its place or is already owned by
`docs/design.md`/`CLAUDE.md`, then the cross-cutting sweep (normalize `name:`
frontmatter to the filename stem, re-audit dangling `[[...]]` links
store-wide).

The corpus numbers behind decision 2, to be written into `docs/design.md` as
the rationale for the `Write|Edit|Bash` matcher — they exist nowhere else and
the scratchpad they were computed in does not survive: over 2,441 transcripts
and 22,168 `Bash` tool calls, ~49 calls mutated a real memory store (~22 an
index, ~29 a fact file), including 15 `git checkout`/`restore` and 3 `git rm`
that no `Write|Edit` matcher can see, against 1,190 `Write`/`Edit` calls on
memory files. All but one of the 49 fall in the last five weeks. Of 25 native
auto-memory stores under `~/.claude/projects/*/memory`, exactly one was ever
mutated from Bash (13-month corpus), so the arm's whole value is on gitlore
stores.

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
