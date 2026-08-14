## Current task

No thread is in flight. The unterminated-final-line defect in
`scripts/lib/index-merge.sh` is fixed and covered by three tests that were
red-checked against the unchanged code, and `just precommit` was green over
that state. The next session picks the first item from the remainder.

The two hazards, recorded because the class recurs: `gitlore_index_merge_paths`
read a side's bullets with a bare `read` while `gitlore_index_part` passes a
missing final newline through, so an unterminated side lost its last path from
the path list although the paired bullets file still carried the line — the
presence rule read that gap as a deletion and the merge returned 0 having
dropped the fact. Separately, `git merge-file` also passes a missing final
newline through, verified directly rather than assumed, so
`cat out.pre out.bullets out.post` welded the first bullet onto an unterminated
preamble, again at exit 0.

The other four bare reads in `index-merge.sh` stay bare — they consume
`git ls-files`, `git ls-tree`, a heredoc and `gitlore_order_merge`'s awk
output, all terminated by construction, none reachable by a hand edit. A
repo-wide grep found no other unguarded read of an index file.

## Open decisions

- Whether to compact the memory index from 23.5KB to under 17.1KB. The lever is
  retiring entries and relocating the acted-inline ones into `CLAUDE.md` /
  `shared-claude.md`; shortening fact bodies measures ~2% and does not move the
  index. It rewrites the index every ddaanet repo loads, so it wants an
  explicit go-ahead rather than an inferred one.
- Whether to chase the shared-bats-fixture flake further. In the memory-gate
  integration suite under `--jobs 2`, `make_parent_with_memory` failed its
  `git -C memory rev-parse HEAD` check with the submodule's working tree
  absent. Every other test in that file used the same cached template and
  passed in the same round, so the template was intact either side of it and
  the loss is in that single `cp -a` of the template into the test repo, or
  immediately after. The guard ahead of it, `git submodule status`, exits 0 for
  a submodule whose working tree is missing and so could never have failed —
  only the rev-parse discriminates. Reproduced once in roughly 1800 test
  executions, so any hunt is a long-loop job.
- Which of the three fixes the orphaned-`MERGE_HEAD` brief offers to take —
  read `pending` from `live`, make the stale-merge guard `MERGE_HEAD`-aware, or
  write the state file before the risky work. The brief recommends none
  decisively.
- Whether to cut a release. `edify`'s `memory/ddaanet/MEMORY.md` is still
  unterminated at HEAD, so that store drops the same carrier line on its next
  compose pass until it picks up the fixed plugin. `just release` must run
  unsandboxed or it dies at the marketplace bump.