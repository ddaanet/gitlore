## Open decisions

- Whether `README.md`'s claim that "`docs/design.md` (FR1–FR16, D1–D19) is implemented and tested" should be re-derived or narrowed. The D-range is stale — decisions run to D44 — but whether D20–D44 are each pinned by a test is unverified, so widening the range would assert something unchecked. Re-deriving it means mapping each decision to the test that pins it, which is the `Where · pinned by` discipline the FR/NFR tables already use and the Design Decisions section does not.

## Remaining

- `memory/MEMORY.md` is 25.7KB against Claude Code's 24.4KB loader cutoff, so tail entries are silently dropped from every session. The index hook flags it on every write. Fix by retiring and merging entries, never by shortening lines to hit the number — an under-triggering line is worse than a missing one.
- The `project` interleaving token, named in the pre-split doc as a cheap future extension of the tier manifest (default: project last), was dropped in the split and is recorded nowhere. Left out deliberately as speculative; restore it to D30 or D37 only if tier ordering comes back up.
