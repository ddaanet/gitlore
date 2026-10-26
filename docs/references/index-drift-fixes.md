# Removing a stale tier pointer — the three edits

Which edit removes a pointer line from a composed store, and how the dangling
and orphan reports name it. The projections this follows from are D36, in
[index-composition.md](index-composition.md); this node is the operational
recipe they imply.

**Removing a tier pointer is one of three edits, and the reports name which.**
For a root line `T/P` of an active tier `T`:

- Root at `HEAD` carries it and root keeps another `T/` line: delete it from
  root only; the next compose drops the carrier copy as root's deletion.
- Root at `HEAD` lacks it (an uncommitted take, or added since the last commit):
  delete `P` from `memory/T/MEMORY.md`, then `T/P` from root. Root alone leaves
  the copy, kept and reported as an orphan.
- The deletion leaves root no `T/` line, so the layout adopts the whole carrier
  back, orphans included: settle the tier's orphans, then delete `P` from the
  carrier if it is still there, then from root — or deactivate `T`.

Carrier first, since a carrier edit triggers no compose. "If it is still there"
because a root-first attempt in the third case is adopted back and reported
again after the carrier copy may already be gone. An orphan is the second case
with root already done — a path root at `HEAD` carries never survives a pass —
so it is one edit, like a project line.

`gitlore_dangling_root_fix` picks the case per dangling line, counting the third
per tier, since dangling lines that together are all of a tier's root lines each
leave the others standing; each orphan quotes the prefixed line to add. Past the
report cap the agent's context says that every root index edit re-runs the
report with the rest. Neither report edits anything (D34).
