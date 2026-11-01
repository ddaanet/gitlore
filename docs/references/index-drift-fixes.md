# Removing a stale tier pointer — decision D66

Which edit removes a pointer line from a composed store, and how the dangling
and orphan reports name it. The projections this follows from are D36, in
[index-composition.md](index-composition.md); this node is the operational
recipe they imply.

- Pointer removal — **D66** removing a tier pointer is one of three edits,
  decided by the harness and named per line in the dangling and orphan reports

---

**D66 — Removing a tier pointer is one of three edits, and the reports name
which**

For a root line `T/P` of an active tier `T`:

- Root at `HEAD` carries it and root keeps another `T/` line: delete it from
  root only; the next compose drops the carrier copy as root's deletion.
- Root at `HEAD` lacks it (an uncommitted take, or added since the last commit):
  delete `T/P` from root, then `P` from `memory/T/MEMORY.md`. Root alone leaves
  the copy, kept and reported as an orphan.
- The deletion leaves root no `T/` line, so the layout adopts the whole carrier
  back, orphans included: settle the tier's orphans, then delete `P` from the
  carrier and `T/P` from root in one batch — or deactivate `T`.

Root goes first, or both edits share one batch: a carrier edit composes at the
end of its batch, and a line root still carries is restored there. The third
case takes one batch because root alone is adopted back and the carrier alone is
restored. An orphan is the second case with root already done — a path root at
`HEAD` carries never survives a pass — so it is one edit, like a project line.

`gitlore_dangling_root_fix` picks the case per dangling line, counting the third
per tier, since dangling lines that together are all of a tier's root lines each
leave the others standing; each orphan quotes the prefixed line to add. Past the
report cap the agent's context says that every root index edit re-runs the
report with the rest. Neither report edits anything (D34).

## Rejected alternatives

**Leaving the rule to recall from D36.** The deciding state, root at `HEAD` and
the per-tier count of root lines, is invisible in the working tree, so an agent
reading only the report would guess the edit and meet the same report again.
