# 2026-07-28 — The memory-approval wording moved into one file, discovered externally by a git-config key

Four independent call sites — three internal (`post-tool-use.sh`,
`memory-commit-batch.sh`, `resolve.sh`) plus a hand-synced copy in the `handoff`
plugin — each composed the FR11 approval prompt from scratch, and the internal
three had already drifted once. `reference/memory-approval-clause.txt` now holds
the one canonical fragment (per-file kind — New/Update/Augment/Reduce/Remove —
tier/slug, one-line summary), read via `gitlore_memory_approval_clause()` and
interpolated into each site's own surrounding sentence. `handoff` discovers it
via a new `gitlore.memoryApprovalClauseFile` git-config key, seeded at install
and re-pinned every `SessionStart` — the same mechanism `gitlore.commitCommand`
already uses (D16). No fallback copy on the consumer side, and no silent skip on
a missing key: see D19.
