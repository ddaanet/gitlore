# Deliverable review — prose partition (Layer 1)

Range `b6dbe92..HEAD`, in-scope commits 2fa5328, ba68af9, ac3735f, 06e2323,
1afbac4, 951b83a, plus the CLAUDE.md hunk from ca41cbe. 8523b47 changes no doc.
Accuracy checked against `scripts/lib/resolve.sh`, `scripts/lib/index-sync.sh`,
`scripts/lib/index-compose.sh`, `scripts/resolve.sh`,
`scripts/git-hooks/pre-commit`, `scripts/cc-hooks/*.sh` and `justfile` at HEAD.
Read-only: no repo file edited apart from this report.

Counts: **Critical 0 · Major 2 · Minor 11**

## Major

### M1 — D50's adoption invariant is false for the take path, and tier-stores.md contradicts it

- **Where:** `docs/references/git-hooks.md:159-166`. The contradiction is with
  `docs/references/tier-stores.md:162-166` and
  `scripts/lib/resolve.sh:1665-1693`.
- **Axes:** functional correctness, consistency.
- **The claim:** "Every path that adopts a tier ahead of its pin therefore
  composes the carrier up into the root index first and stages the pair,
  **or stages nothing at all**".
- **What the code does:** `gitlore_adopt_tier_into_root` is the tail of both
  take branches (`resolve.sh:1524`, `:1654`). When `gitlore_compose_up` returns
  non-zero it prints the failure, then still runs
  `gitlore_git -C "$mempath" add -- MEMORY.md "$tier"` and
  `gitlore_commit_tier_bookkeeping`.
- **Where else it breaks:**
  - The merge continuation (`scripts/resolve.sh:125-141`) also stages after an
    up refusal ("the merge is being committed without the adopted tier's
    lines").
  - `tier-stores.md` says every advancing path stages the pair. It makes no
    exception for a failed up projection.
  - The comment at `resolve.sh:285-287` names `gitlore_adopt_tier_into_root` as
    "the precedent" for stage-nothing-on-failure. That function does not follow
    the rule.
- **Consequence:** the design record states one invariant and the code has
  another, and two nodes disagree.
  - A reader who audits the take path against D50 will call it compliant.
  - A reader who makes the code comply ("stage nothing") breaks the staging that
    `tier-stores.md` argues keeps `SessionStart` from walking the tier back.
  - Which side is right is a design call: narrow the D50 sentence to the
    recovery path, or change the take's failure arm. Either way the hazard D50
    names is live after a refused take once the store is fixed by hand. The down
    pass then projects root's older text for any line whose hook changed
    upstream.

### M2 — CLAUDE.md's gate-file fallback reports a false green on exactly a docs-only commit

- **Where:** `CLAUDE.md:62-70`, from ca41cbe.
- **Axes:** functional correctness, completeness.
- **The claim:** read the `just precommit` verdict from
  `.git/gitlore/gates/{lint,test-unit,test-integration,check-distribution}`,
  each "valid for the tree when its mtime postdates the last edit to any gated
  input".
- **What `precommit` actually runs** (`justfile:48-59`):
  - `format-docs`
  - `scripts/check-memory-hygiene.py`
  - `scripts/check-docs-links.py`
  - `check-version`

  None of the four has a gate file. `docs/` and `memory/` are out of
  `precommit_inputs` (`justfile:15-19`).
- **How the false green happens:**
  1. A docs-only edit breaks `check-docs-links.py`.
  2. `precommit` stops before `just check-version lint test`.
  3. The earlier `lint`/`test-*` sentinels are untouched.
  4. No gated input was edited, so the mtime rule calls them valid.
  5. The subagent reports a pass.

  That is the shape of every Phase 4 commit. Right now the working tree fails
  `check-docs-links.py` with rc=1, from untracked `docs/plans/` and
  `docs/superpowers/` files over the size cap. Meanwhile all four gate files
  postdate the last gated-input edit and would read as green.
- **Secondary problems:**
  - Validity is really a hash match (`check-sentinel`, `justfile:169-179`), not
    an mtime. The mtime proxy is too permissive when a gated file is deleted or
    a tool version changes.
  - The path is hard-coded to `.git/gitlore/gates`, but the recipe resolves
    `git rev-parse --git-path gitlore/gates`, which is per-worktree in a linked
    worktree.
  - The "Only if the run dies" fallback (`just lint`, `just test-integration`,
    `just test-unit`) leaves out `check-distribution` and all four uncached
    checks. It does not reproduce `precommit`.
- **Consequence:** a subagent commits over a failing docs-graph or hygiene
  check, believing the gate passed.

## Minor

### m1 — the `pre-commit` step list reads out of execution order

- **Where:** `docs/references/git-hooks.md:50-57`.
- **Axis:** usability.
- **Problem:** the list says "in this order", but step 3 (compose, tier sync)
  runs *after* step 4's dirty/freshness gate and pin guard
  (`resolve.sh:963-1091`). The corrector's line-neutral patch ("which is what
  runs step 3") makes step 4 point backwards. Step 4's chain also leaves out the
  tier sync between the down composition and `add -A`. The node is now 189
  lines, so the 400/400 constraint behind that patch is gone.
- **Consequence:** a reader ordering a new guard against the list places it
  wrongly.

### m2 — the changelog's sequence skips the tier sync

- **Where:**
  `docs/changelog/2026-09-11-the-commit-path-composes-before-it-commits.md:13`.
- **Axis:** accuracy.
- **Problem:** `dirty/freshness gate → pin guard → compose → add -A → …` leaves
  out `gitlore_sync_tiers_to_live`. The corrector fixed this defect in the node
  (its fix 7) but not here. The next sentence then argues the placement ahead of
  that very step.
- **Consequence:** the changelog's sequence contradicts its own next sentence.

### m3 — "a sixth untracked `gitlore-…` file" undercounts

- **Where:** changelog entry `:64-65`. The same count is in the comment at
  `scripts/lib/index-sync.sh:111`.
- **Axis:** accuracy.
- **Problem:** besides the five files named, the gitdir already holds:
  - the three `gitlore-merge-<artifact>` files;
  - `gitlore-budget-nudged-<session>` and `gitlore-upgrade-nudged-<session>`
    (`index-sync.sh:412`, present since 2026-07-31).
- **Consequence:** a wrong count in the write-time record. Harmless alone, but
  counts like this get copied.

### m4 — the relay's write contract and residual are not recorded in the node

- **Where:** `docs/references/index-authoring-sync.md:104-115`.
- **Axis:** completeness (FR-D).
- **Problem:** the node states the pre-image's bounded residual but none of the
  following, all of which live only in script comments:
  - 8523b47's atomic install: build at `$marker.tmp`, `mv`, refuse a directory
    squatting the marker path.
  - The drain's `*.tmp` exclusion.
  - The new residual: one stranded temp per agent whose first write died.
  - The merge-not-truncate write (two `PostToolBatch` hooks stage to one key).
  - The relay-failure line on `additionalContext`.

  `docs/references/configuration.md:42-44` still lists gitdir hook state as only
  `gitlore-nudged` and the merge-state file. That is the corrector's item D,
  left unfixed.
- **Consequence:** the record's lifecycle story ends at "removes them". A reader
  who finds `gitlore-relay-*.tmp` in a gitdir, or who plans to simplify the
  write back to a redirect, has nothing in `docs/` saying why it is not a leak
  or why it must stay atomic.

### m5 — alternatives argued at paragraph length are not named as rejected

- **Where:** `docs/decisions.md:56-57` and `:116-118`;
  `docs/references/git-hooks.md:175-189`; `docs/references/cc-platform.md:202+`.
- **Axis:** conformance (CLAUDE.md: every rejected alternative by name).
- **Unnamed alternatives:**
  - Composing a clean store too (D50 body, "Dirty stores only").
  - Reporting a non-empty commit-path compose result (D50, "stays silent").
  - Relaying *instead of* the subagent's own emission (argued in the outline §D
    and `index-authoring-sync.md:112`).
- **Also:** D50's conclusion lines leave out the dirty-only scope, which the
  runbook's Item 4.1 lists as part of the decision.
- **Consequence:** these are the likeliest to be re-proposed. The index is the
  file read before weighing a new decision, and it does not show them.

### m6 — D51 says "all four" without saying four of what

- **Where:** `docs/references/cc-platform.md:188`.
- **Axis:** usability.
- **Problem:** "the subagent's own JSONL carries all four" refers to a count
  defined only in the probe under `plans/`, which docs may not cite.
- **Consequence:** the one shipped statement of the measurement is not
  self-contained. Two hooks times two channels would say it.

### m7 — session.md steps 6 and 10 disagree about fast-forward failures

- **Where:** `docs/references/session.md:84-86` against `:109-111`.
- **Axis:** consistency.
- **Problem:** step 6 says "A fast-forward that fails is divergence" and never
  says it exits. Step 10 relies on "the early exits above — divergence, a failed
  fast-forward" as two cases. The script separates them and both exit early
  (`session-start.sh:194-208`).
- **Consequence:** step 10 points back at exits that step 6 does not describe.
  Step 6's merge of the two cases is pre-existing, but step 10 now builds on it.

### m8 — the recovered-merge adoption paragraph covers only the checkout case

- **Where:** `docs/references/merge-state-recovery.md:80-84`.
- **Axis:** accuracy.
- **Problem:** "Putting HEAD back on the merge leaves the enclosing store's
  index still naming…" frames adoption as following the checkout. It also fires
  when HEAD already contains the landed merge and nothing is checked out
  (`resolve.sh:237-242`).
- **Consequence:** a reader concludes the no-checkout arm skips adoption.

### m9 — the hub does not mention the subagent relay

- **Where:** `docs/design.md:205-218`, the Claude Code hooks bullet.
- **Axis:** completeness.
- **Problem:** the bullet lists what `PostToolBatch` and `SessionStart` do. It
  says nothing of the per-agent keying or the relay drain, which is user-visible
  behaviour of both. D51 is reachable only through `decisions.md`.
- **Consequence:** a reader of the architecture summary does not learn that a
  subagent's reports reach the parent through a marker. Many decisions are
  absent from the hub, so this is Minor.

### m10 — D51 links to a paragraph with no locator

- **Where:** `docs/references/cc-platform.md:196-197` →
  `docs/references/index-authoring-sync.md:104`.
- **Axis:** usability.
- **Problem:** the relay mechanism, which covers the compose hook's report too,
  sits unheaded inside D38's body ("Authoring-time sync is one-way"). The link
  gives no locator.
- **Consequence:** a reader who follows D51's pointer has to search a 314-line
  node for a paragraph under an unrelated decision.

### m11 — CLAUDE.md cites `plans/`

- **Where:** `CLAUDE.md:61`.
- **Axis:** conformance.
- **Problem:** it cites
  `plans/index-edit-propagation/background-run-timeout-probe.md`, and `plans/`
  is swept.
- **Consequence:** the citation breaks when the plan directory is swept.

## Outside this partition — script comments

- **`scripts/lib/index-sync.sh:139-141`** says "the redirect below is the single
  write, so a failed open leaves nothing on disk to clean up". That is stale
  since 8523b47: a failed write can leave `$marker.tmp`.
- **`scripts/lib/index-compose.sh:297`** says "only gitlore_compose calls it"
  (`gitlore_compose_check_pins`). `gitlore_sync_memory_to_live` calls it too
  (`resolve.sh:1001`).

## The corrector's fixes hold

- **Fixes 1–7:** all present at HEAD. Fix 1's ordering fix moved into
  `git-hooks.md` with the split; fix 7's chain is at
  `memory-entry-points.md:38-41`.
- **Out-of-scope A** (D31 said three triggers): closed by 1afbac4. D31 says four
  points, the off-pin rule names the commit path, and D36's Down bullet lists
  the commit path.
- **Out-of-scope B** (session step list had no drain): closed by step 10.
- **Out-of-scope C** (`index-sync-pre.sh` residual comment): closed.
- **Out-of-scope D** (`configuration.md`): still open, see m4.

## Checks that passed

- **Old node name.** No inbound reference to `git-hooks-and-entry-points`
  outside `plans/` and git history. The only hits are dated changelog entries
  (history, plain text, not links) and `.claude/handoff-todo.md` (tooling,
  prose).
- **Links and decision graph.** `python3 scripts/check-docs-links.py` reports
  broken-link, unstubbed-decision, stub-without-body, duplicate-decision,
  duplicate-conclusion, undefined-decision, enumeration-drift and
  delegation-drift all 0. Its rc=1 comes from 11 oversized files, all untracked
  `docs/plans/` and `docs/superpowers/` files not in HEAD. None of the changed
  docs uses a `#anchor` link.
- **Decision records.** D50 and D51 each have:
  - one conclusion bullet in `decisions.md`;
  - rejected alternatives by name on their group line, mirrored under the node's
    `## Rejected alternatives`;
  - a group link to the node holding the argument.

  Headings and titles enumerate them (`git-hooks.md` D46, D50; `cc-platform.md`
  D15, D18, D23, D51; `memory-entry-points.md` D16, D20). The wording agrees
  across the hub, the index, the node heading and the node summary bullet.
- **Trigger count.** Four compose trigger points wherever they are enumerated
  (`index-composition.md` D31 and D36). "Three callers" appears only in the
  changelog entry's past-tense history, and it counts `gitlore_compose` callers,
  not triggers.
- **Hub.** `design.md` gives D50 one summarizing clause and does not argue it.
- **Tense.** Added lines in `docs/references`, `design.md` and `decisions.md`
  contain no "previously", "no longer" or "now" correction framing.
- **Size and wrap.** Every changed file is under 400 lines (largest:
  `session.md` 381). Every prose line is within 80 characters; the only overruns
  are pre-existing code-block lines in `session.md`.
- **Citations.** No `plans/`, `memory/`, runbook, slice or line-number citations
  in the changed docs. `design.md:15` names `plans/` as a location, not a
  citation.
- **Verified true against the scripts:**
  - D50 ordering: pin guard ahead of compose, compose ahead of the tier sync.
  - Dirty-only scope.
  - rc-1 reports and proceeds; rc-2 and unknown statuses abort and restamp; the
    pin abort does not restamp.
  - The pin abort names no remedy of its own.
  - Per-agent keying through `_gitlore_agent_suffix`; `agent_id` read, never
    `agent_type`, in all five hooks.
  - The drain runs only on a batch that changed the index or manifest, with
    `session-start.sh` as backstop and its early exits skipping the drain.
  - `gitlore_adopt_recovered_merge`: compose up, stage the named pair, stage
    nothing on failure, tier only.
- **Requirement coverage:**
  - FR-B, FR-F (D50) and FR-C (`index-authoring-sync.md`) are recorded.
  - FR-D's measurement (D51), relay and SessionStart drain are recorded.
  - FR-D's atomic install from 8523b47 is not (m4).
