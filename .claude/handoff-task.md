## Current task

Nothing is mid-flight. `plans/brief-memory-index-glued-bullets.md` is fully
applied — request 4, the `PreToolUse`/`PostToolUse` pair on `Edit`, landed in
`32ea556` with `scripts/lib/edit-weld.sh`, `scripts/cc-hooks/edit-weld-pre.sh`
and `-post.sh`, 32 tests across `tests/edit_weld.bats` and
`tests/cc_hook_edit_weld.bats`, and D23 in `docs/design.md`. Dogfooded end to
end against a real welding `Edit`, which repaired and reported on both
channels.

Three departures from the brief's decided design, each measured rather than
argued and each recorded in D23. `updatedToolOutput` is unused: `Edit`'s
model-visible result is a fixed success string carrying no diff, so nothing in
the agent's model of the file is there to correct. The arming test is narrower
than the brief's "risky shape" — the match must also be FOLLOWED by a newline.
And `replace_all` disarms.

The next item is a choice among the remaining briefs, not a continuation of
this one.

## Open decisions

- **The memory index is past Claude Code's loader cutoff.** `memory/MEMORY.md`
  is 25.1KB against the 24.4KB point where the loader silently truncates, and
  the budget hook now fires on every index write demanding under 17.1KB.
  Composition orders tier-first, so it is this project's own lines that fall
  past the cutoff. The lever is retiring entries and relocating the
  acted-inline ones into `CLAUDE.md` / `shared-claude.md`; shortening fact
  bodies measures ~2% and does not move the index. It rewrites the index every
  ddaanet repo loads, so it wants an explicit go-ahead.
- Whether to chase the shared-bats-fixture flake further. In the memory-gate
  integration suite under `--jobs 2`, `make_parent_with_memory` failed its
  `git -C memory rev-parse HEAD` check with the submodule's working tree
  absent, while every other test in the file used the same cached template and
  passed in the same round. The guard ahead of it, `git submodule status`,
  exits 0 for a submodule whose working tree is missing, so only the rev-parse
  discriminates. Reproduced once in roughly 1800 executions — a long-loop hunt.
- Which of the three fixes the orphaned-`MERGE_HEAD` brief offers to take.
  The brief recommends none decisively.
- Whether to cut a release. `edify`'s `memory/ddaanet/MEMORY.md` is still
  unterminated at HEAD, so that store drops the same carrier line on every
  compose pass until it picks up the fixed plugin. `just release` must run
  unsandboxed or it dies at the marketplace bump.