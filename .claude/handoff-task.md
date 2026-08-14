## Current task

Applying `plans/brief-memory-index-glued-bullets.md`. Requests 1 and 2 are done
— the welded-bullet refusal in `gitlore_compose_check_index` and the `](`
refusal in the authoring-time sync. Request 3 landed earlier alongside the
unterminated-final-line fix and must not be applied again. **Request 4 is what
resumes**: a `PreToolUse`/`PostToolUse` pair on `Edit` that computes the
intended result of a risky-shaped call, repairs the file when the two differ,
and reports when they stop differing so the pair can retire. The brief carries
the decided design in full; read it rather than re-deriving.

Two findings bear on that work. The `Edit` defect **still reproduces at CC
2.1.232** — `A\nX\nB\n` minus `"\nX"` with an empty `new_string` yields `AB\n`,
verified on a fixture this session — so the repair path fires rather than
sitting idle. And `updatedToolOutput`, which the brief treats as load-bearing
on that path, is **validated against the tool's own output shape** and rejected
on mismatch (`PostToolUse hook returned updatedToolOutput that does not match
<tool>'s output shape`). Establishing `Edit`'s result object is a prerequisite,
not a detail; the finding is recorded in `ddaanet/hook-cannot-inject-tool-calls`.

## Open decisions

- **The memory index is at 100% of its 25600-byte budget**, with no headroom
  left. The `ddaanet` tier index alone is 24,867 B and composition orders
  tier-first, so it is this project's own lines that fall past Claude Code's
  24.4KB loader cutoff and never reach a session. The lever is retiring entries
  and relocating the acted-inline ones into `CLAUDE.md` / `shared-claude.md`;
  shortening fact bodies measures ~2% and does not move the index. It rewrites
  the index every ddaanet repo loads, so it wants an explicit go-ahead.
- Whether to chase the shared-bats-fixture flake further. In the memory-gate
  integration suite under `--jobs 2`, `make_parent_with_memory` failed its
  `git -C memory rev-parse HEAD` check with the submodule's working tree
  absent. Every other test in that file used the same cached template and
  passed in the same round, so the loss is in that single `cp -a` of the
  template into the test repo, or immediately after. The guard ahead of it,
  `git submodule status`, exits 0 for a submodule whose working tree is
  missing and so could never have failed — only the rev-parse discriminates.
  Reproduced once in roughly 1800 test executions, so any hunt is a long-loop
  job.
- Which of the three fixes the orphaned-`MERGE_HEAD` brief offers to take —
  read `pending` from `live`, make the stale-merge guard `MERGE_HEAD`-aware, or
  write the state file before the risky work. The brief recommends none
  decisively.
- Whether to cut a release. `edify`'s `memory/ddaanet/MEMORY.md` is still
  unterminated at HEAD, so that store drops the same carrier line on its next
  compose pass until it picks up the fixed plugin. `just release` must run
  unsandboxed or it dies at the marketplace bump.