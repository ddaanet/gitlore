## Open decisions

- Whether `README.md`'s claim that "`docs/design.md` (FR1–FR16, D1–D19) is implemented and tested" should be re-derived or narrowed. The D-range is stale — decisions run to D44 — but whether D20–D44 are each pinned by a test is unverified, so widening the range would assert something unchecked. Re-deriving it means mapping each decision to the test that pins it, which is the `Where · pinned by` discipline the FR/NFR tables already use and the Design Decisions section does not.
- What the split review's remaining passes should cover, now the loss pass is closed. Candidates: whether `scripts/check-docs-links.py`'s seven checks cover what a graph can silently break (its conclusion-coverage check accepts a node's own summary bullet in place of a hub bullet, which is what let D41 lose its hub conclusion), and whether each node's opening framing still describes what that node holds.

## Remaining

- `memory/MEMORY.md` sits at 104% of the 25600-byte budget, past Claude Code's 24.4KB loader cutoff, so tail entries are silently dropped from every session and the index hook flags it on every write. Fix by retiring and merging entries, never by shortening lines to hit the number — an under-triggering line is worse than a missing one.
- The `project` interleaving token, named in the pre-split doc as a cheap future extension of the tier manifest (default: project last), was dropped in the split and is recorded nowhere. Left out deliberately as speculative; restore it to D30 or D37 only if tier ordering comes back up.
