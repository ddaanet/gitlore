## Open decisions

- Whether `README.md`'s claim that "`docs/design.md` (FR1–FR16, D1–D19) is implemented and tested" should be re-derived or narrowed. Decisions run to D44; whether D20–D44 are each pinned by a test is unverified, so widening the range would assert something unchecked. Re-deriving means mapping each decision to its pinning test, the `Where · pinned by` discipline the FR/NFR tables use and Design Decisions does not.
- What the split review's remaining passes should cover: whether each node's opening framing still describes what that node holds after the second split, and whether `check_coverage` accepting a node's own summary bullet in place of a hub bullet (what let D41 lose its hub conclusion once) still needs tightening now the hub carries every bullet again.

## Remaining

- Fix `check_orphans` in `scripts/check-docs-links.py` to resolve sibling-relative links from nodes (a link target with no directory, or `./x.md`, from a file under `docs/references/` cites `references/x.md`); add a bats case in `tests/check_docs_links.bats` where a node is linked only from a sibling and must not warn, and one where nothing links it and must. Then the 2026-08-25 changelog entry may drop the full-path evals citations it carries only to clear the warning.
- `memory/MEMORY.md` sits past the 25600-byte budget and Claude Code's 24.4KB loader cutoff, so tail entries are silently dropped every session and the index hook flags every write. Fix by retiring and merging entries, never by shortening lines to hit the number.
- The `project` interleaving token, named in the pre-split doc as a cheap future extension of the tier manifest (default: project last), is recorded nowhere. Restore it to D30 or D37 only if tier ordering comes back up.
- `format-docs` reports lines it cannot wrap on every run (long code spans and a table row in `docs/references/installation.md:122`, `session.md:100`, `plans/2026-05-31-08-install-rough-edges.md`); reword or split them if the noise earns it.
