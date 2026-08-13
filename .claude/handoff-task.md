## Current task

Nothing is mid-flight. Two threads are parked: an unexplained flake in the
shared bats fixture, and the brief backlog in the todo file.

The flake: in the memory-gate integration suite under `--jobs 2`,
`make_parent_with_memory` failed its `git -C memory rev-parse HEAD` check with
the submodule's working tree absent. Every other test in that file used the
same cached template and passed in the same round, so the template was intact
either side of it and the loss is in that single `cp -a` of the template into
the test repo, or immediately after. The guard ahead of it, `git submodule
status`, exits 0 for a submodule whose working tree is missing and so could
never have failed — only the rev-parse discriminates. Reproduced once in
roughly 1800 test executions.

## Open decisions

- Whether to compact the memory index from 23.5KB to under 17.1KB. The lever is
  retiring entries and relocating the acted-inline ones into `CLAUDE.md` /
  `shared-claude.md`; shortening fact bodies measures ~2% and does not move the
  index. It rewrites the index every ddaanet repo loads, so it wants an
  explicit go-ahead rather than an inferred one.
- Whether to chase the fixture flake further. At roughly one failure per 1800
  test executions, any hunt is a long-loop job.
- Which of the three fixes the orphaned-`MERGE_HEAD` brief offers to take —
  read `pending` from `live`, make the stale-merge guard `MERGE_HEAD`-aware, or
  write the state file before the risky work. The brief recommends none
  decisively.
- Whether to cut a release. `edify`'s `memory/ddaanet/MEMORY.md` is still
  unterminated at HEAD, so that store drops the same carrier line on its next
  compose pass until it picks up the fixed plugin. `just release` must run
  unsandboxed or it dies at the marketplace bump.