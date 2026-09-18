# Phase 7 corrector — docs

Scope: the uncommitted diffs to `docs/changelog.md`,
`docs/references/{commit-gate,git-hooks,index-authoring-sync,merge-and-resolve,tier-arrival-repair,tier-stores}.md`
and the new
`docs/changelog/2026-09-18-repair-and-continuation-failures-say-what-they-left.md`.
Nothing committed.

## Verified against the shipped code

- `gitlore_adopt_repair_arrival` (scripts/lib/resolve.sh:1948): scratch is
  `mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"`; each transient arm
  (scratch, arrival read, pin read, rewrite, commit build, `live` advance,
  checkout follow) prints its own line, then the full refusal via
  `gitlore_adopt_report_refusal_and_walk_back` with `Run /gitlore:merge again.`
- `the repair` is passed by exactly two arms: the checkout that could not follow
  the advance, and the refused retry (whose remedy stays the default
  `Fix the store, then run /gitlore:merge again.`). The `live`-advance failure
  keeps `what arrived`. The docs say this.
- Unrepairable arm: carrier lines as `live:MEMORY.md: …`, other lines under the
  root-index header, two-fix remedy only when other lines exist. Matches
  tier-arrival-repair.md:95-102 verbatim.
- `gitlore_push_stores`: the behind arm still pushes its own tier in-arm when
  `live` is not an ancestor of `origin/live`; the post-loop pass pushes every
  tier whose `live` is not an ancestor of `origin/live` (or has none) before
  memory's push. `gitlore_report_tier_push_failure` keeps the moved-remote
  wording for `(fetch first)`/`(non-fast-forward)` and says
  `not because of divergence` otherwise. Docs match.
- `continue-after-merge` (scripts/resolve.sh:308-330): the three
  `… so the merge was not committed; the merge stays prepared.` lines; the
  merged-index refusal carries its own longer line. Merger
  (agents/memory-merger.md:37-43) and skill (skills/resolve/SKILL.md:68-73)
  branch on exit 0 first, route the named lines, and call anything else
  unrecognised. Docs match.
- "Before" claims checked against `3502a86` (the commit before this job):
  scratch lived in `$gitdir/gitlore-repair.XXXXXX`; transient arms called
  `gitlore_adopt_walk_back_tier` with no remedy (default `Fix the store, …`) and
  printed no refusal; the walk-back hard-coded `keeps what arrived`; the
  unrepairable arm printed only carrier lines; the old merger read every exit
  without the merged-index line as landed. Terminator: `a631b6e` shows the old
  code printed the output's final element without a newline whenever the input
  was unterminated, whatever element ended up last.

## Fixes applied

1. **Changelog entry, "before" paragraph — inaccurate.** It said a walked-back
   repair "printed only the carrier's problems"; the transient arms printed none
   of the refusal, and only the unrepairable arm printed carrier problems. Split
   into the two cases, and attributed `keeps what arrived` to every walk-back
   rather than to the transient arms (the refused retry, which also held the
   repair, is not transient).
2. **Changelog entry and index line, terminator — inaccurate.** "keeps each
   line's own terminator" and "left a line that stopped being last without its
   newline" invert the defect: the line that *became* last lost the newline it
   had, and a moved stray past an unterminated last bullet now terminates both
   (so not every line keeps its own terminator). Entry now states the output is
   unterminated only when the input's own unterminated last line is still last;
   index line reads "the repair no longer strips the newline from a line it
   leaves last".
3. **merge-and-resolve.md and the changelog entry: "a merge commit a hook
   refuses"** → "a refused merge commit". The arm fires on any `git commit`
   failure (the emitted text is "the merge commit was refused"), not only a
   hook.
4. **merge-and-resolve.md: "a rerun lands the merge"** → "a rerun once that
   cause is fixed lands the merge". The skill routes these lines to
   **Summarize**, not **Loop**, because a bare rerun meets the same refusal.
5. **tier-stores.md walk-back list — incomplete.** "The tier walks back only
   when …" omitted the `live` advance and checkout-follow failures, which the
   next sentence then names as holding the repair. Added "when `live` cannot
   take it or the worktree cannot follow".

## Sweep (item 7.4)

`rg -n` over `docs/` and `skills/` for `keeps what arrived`,
`Fix the store, then run`, `not because of divergence`,
`the merge was not committed`, `gitdir` beside `repair`/`scratch`,
`both push arms`, `four nodes`, `four sibling`, `of the (four|five) nodes`,
`any other reason`: every remaining hit is true of the code. `tiered-memory.md`
"four sibling(s)" is correct (index-composition, index-authoring-sync,
tier-stores, tier-arrival-repair; merge-and-resolve is cited for D41, not listed
as a sibling). `docs/design.md` (:52-54, :199-200) and `docs/decisions.md`
(:136, :151-154) carry no D52 publication wording.

Noted, not fixed (out of scope — `skills/` already reviewed):
`skills/merge/SKILL.md:72-74` says an unrepairable arrival "must be fixed where
it was published", without the two-fix case, and does not mention the
transient-failure remedy. Incomplete rather than false.

## Style and size

No `now`/`no longer`/correction framing, and no `plans/`, `memory/` or slice
citations, in the reference-node diffs (the changelog is exempt). Sizes:
tier-arrival-repair 182, tier-stores 313, merge-and-resolve 374,
index-authoring-sync 375 — all under 400. The index line's format matches its
neighbours.

## Gates

`just format-docs`: `Fixed 6/205 issues in 4 files` (reflow of the edits).

`python3 scripts/check-docs-links.py` (the justfile's docs-link step), rc 0:

```text
check-docs-links: 52 decisions, 121 files scanned
  broken-link          0
  unstubbed-decision   0
  stub-without-body    0
  duplicate-decision   0
  duplicate-conclusion 0
  undefined-decision   0
  enumeration-drift    0
  delegation-drift     0
  oversized-file       0
```

UNFIXABLE: none.
