# 2026-07-25 — Root↔carrier composition became a path-keyed three-way merge, replacing two point-fixes that each guessed one direction

The root's tier block and the tier's carrier index are two projections of the
same facts, and either side can move between passes — the agent edits the root,
a propagation-in fast-forward moves the carrier. From two snapshots a path
present in one but not the other is ambiguous: an add on this side and a delete
on the other are indistinguishable, so a two-way reconcile has to pick a
direction and is wrong the other way. `gitlore_compose_tier_bullets` now merges
root (ours) and carrier (theirs) against a **base**, keyed on the pointer path
rather than the line text, so a hook-only divergence resolves by the
canonical-index rule (root wins) instead of false-conflicting. Presence: a path
at base survives only if **both** sides keep it (a delete on either side wins);
a path new since base survives if **either** side added it. Adds and deletes
therefore propagate in both directions — including deleting a tier fact by
removing its root bullet — and file presence is never consulted by the merge
(the dangling *report* still consults it, orthogonally). The base is the carrier
**as of the last compose**, in `refs/gitlore/compose-base` in the tier (a ref,
so the blob is a GC root), refreshed by `gitlore_compose_save_base` at the end
of every successful pass. It tracks composes, not commits, deliberately: root
composition floats behind a commit, so the committed gitlink and `HEAD` both run
*ahead* of what root reflects and read a not-yet-projected add as a delete — two
earlier base picks (tier `HEAD`, then the memory gitlink) failed exactly there
and resurrected deletions. Retired: the carrier-line-not-in-root **drop**
(`420d9dc`), which propagated a root deletion but ate an upstream addition once
the root block was non-empty, and the **file-presence gate**, which propagated
an upstream deletion but could not express a delete-via-root-bullet. The live
20-line `ddaanet` divergence had fired both at once. Also shipped: the dangling
report is capped (`gitlore_cap_list`, `GITLORE_DANGLING_CAP` default 5) on both
the `SessionStart` `systemMessage` and the compose `additionalContext`, and
`SessionStart` gained a capped agent-facing "index is STALE" notice. The live
`ddaanet` tier was healed in the same pass — one unpushed local commit
(`cabd7c6`) had reconciled a good 78-bullet carrier down to a stale root;
`origin/live` was always clean, so recovery was `branch -f live origin/live`
plus a wholesale re-projection of the 78 bullets, and the corrupt commit stayed
unreachable and never reached the remote.
