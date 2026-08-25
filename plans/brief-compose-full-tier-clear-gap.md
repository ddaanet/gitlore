## Brief: compose can't distinguish a full-tier clear from never-spliced

2026-07-24

### Decisions

- Fixed the resurrection bug this gap is a residue of:
  `gitlore_compose_tier_bullets` (`scripts/lib/index-compose.sh:253-296`) now
  drops a carrier line when root has *some* bullets for that tier but not this
  specific one — gated on `[ -z "$rootbullets" ]` (empty → preserve; non-empty →
  root is authoritative, drop what's missing). Confirmed live: stashing the fix
  and re-running the new test reproduced the resurrection on unmodified `main`
  (`cd0319b`).
- Chosen shape, per David: "transparently support observed agent behavior," not
  "block and tell the agent to hold it better" — the agent edits root only (the
  documented write path), the system completes the removal, no warning message
  telling the agent to also touch the carrier.
- `PostToolBatch` `additionalContext` in `gitlore_compose_and_report` updated to
  say compose "drops any carrier line whose root counterpart is gone" — this
  part is shipped, not part of the remaining gap.

### Constraints

- Compose is placement-only: it may reorder/mirror/drop *index lines*, but must
  never create or delete a memory *file*.
- Must not regress the deliberate dormant-tier and brand-new-tier preservation
  behavior (`tests/index_compose.bats`: "a dormant tier still receives
  mirror-down, so no root line is lost", "splice up: an active tier's carrier
  bullets appear prefixed in the root").
- `gitlore_compose` (`scripts/lib/index-compose.sh:425`) runs mirror-down
  (root→carrier, per tier) THEN splice-up (rebuilds root's *entire* active-tier
  block from the just-mirrored carriers). This ordering is why the fix's gate
  has to be about root's *current* content, not tier active/dormant status.

### Rejected approaches

- Gating the drop on "is this tier active" instead of "does root have any
  bullets for it" — traced through the mirror-down→splice-up ordering, this
  wipes a tier's *entire* carrier the instant it's (re)activated, before
  splice-up ever gets to populate root from it. Root's own current content is
  the only safe signal available.
- A report-only warning telling the agent to also edit the carrier by hand —
  rejected as the wrong shape (see Decisions).

### Additional context

**The remaining gap**: if an agent deletes *every* root-authored bullet for an
ACTIVE tier in one edit, `rootbullets` for that tier becomes empty — which is
exactly the signal the fix uses to mean "never spliced yet, preserve the
carrier." So a full clear-in-one-shot doesn't propagate: the carrier survives
intact, and the next splice-up resurrects all of it back into root. This is
the mirror image of the bug just fixed, but narrower — it only bites clearing
an entire tier's root block at once, not the realistic partial-dedup case
(removing a few facts among several), which the fix already handles and
`tests/index_compose.bats` "removing an active tier's root line drops it from
the carrier in one pass" now covers.

Root cause of why this can't be closed with the same trick: the merge function
only sees CURRENT root/carrier content on each call — there's no persisted
"was this tier previously synced" state, so "just activated, never spliced"
and "was fully established, now emptied" look identical from inside
`gitlore_compose_tier_bullets`.

Options to evaluate, not yet decided:
1. Accept and document the gap (current status — narrow, avoidable by not
   emptying a tier in one edit).
2. A persisted last-synced marker per tier (e.g. a generation counter or a
   cached snapshot compose writes on each pass), so "previously non-empty, now
   empty" is distinguishable from "never populated."
3. Detect the touch via the actual tool-call diff (old vs new file content)
   rather than post-hoc file comparison — a deeper change to how
   `index-compose.sh`'s `PostToolBatch` handler decides what changed.
4. Require a full-tier clear to go through an explicit action (deactivate /
   remount) instead of hand-editing every line out of root.

No code changes have been made for this gap — it's flagged, not started.
