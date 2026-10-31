# Design history — decision D72

How the design's history is kept: git history is the changelog, and a decision
that is inverted or retired is deleted rather than annotated. There are no dated
records and no index of them.

- **D72** — git history is the design's changelog: the dated records and both
  indexes are deleted, a design-significant change carries its why in the commit
  body or the node, and an inverted or retired decision is deleted from
  `decisions.md` and its node, with the deleting commit saying why and the
  number never reused

---

**D72 — Git history is the design's changelog**

A dated record restated the commit it landed with: 123 of the 124 records were
added in the commit that made the change they describe. The project's rule for a
summary of a change is that it points at the diff and does not narrate it, and a
record that narrates the diff is the thing that rule removes. Keeping the
records also kept two index files that the hub linked and the size check
counted, for a history `git log` already holds.

So the dated records and both indexes are gone. What a record sometimes carried
that its commit did not is the why, and the why now goes where a reader meets
the change: in the commit body, or, when the reasoning is part of how the system
works, in the node that argues the decision. A commit without a body is
acceptable only for a change whose why the diff states.

An inverted or retired decision follows the same rule. It is deleted from
`decisions.md` and from its node; the deleting commit says why, and the diff
keeps the text. The decision's number is not reused, so a gap in the D-numbers
is a retirement and nothing else. A reader looking for a deleted decision finds
it with `git log -S` on its number, and a deleted record with
`git log -- docs/changelog.md docs/changelog-archive.md docs/changelog/`, then
`git show <deleting-commit>^:docs/changelog/<file>`, the deleting commit being
the one whose body gives that recovery.

## Rejected alternatives

**Keeping the existing records frozen while writing no new ones.** The craft
design-doc rules permit it. A frozen index is still a file the hub links and the
size check counts, and it asks every reader to learn that the records stop at a
date.

**Splitting `changelog.md` by period to pass the size check.** It keeps the
record the first decision removes, in more files, to satisfy a measure.

**A "retired decisions" section in `decisions.md`.** It turns the index a reader
holds in full while weighing a new decision into a store of decisions that no
longer bind, and each entry there is a conclusion the reader has to discount.
