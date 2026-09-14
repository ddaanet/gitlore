# Deliverable review — prose and config partition (fresh, post fix pass)

Counts: **Critical 0 · Major 1 · Minor 10**

## Scope

- **Range:** `b6dbe92..HEAD`, including the fix pass 7485483, 081e364, e36e7fc,
  38de36b, 45624bd and 7d20aab.
- **Files:**
  - `docs/decisions.md`: the D50 and D51 hunks only.
  - `docs/design.md`: the Claude Code hooks and Git hooks bullets.
  - `docs/references/`: `git-hooks.md`, `memory-entry-points.md`,
    `index-authoring-sync.md`, `index-composition.md`, `cc-platform.md`,
    `session.md`, `commit-gate.md`, `merge-state-recovery.md`, `tier-stores.md`
    and `configuration.md`.
  - `docs/changelog.md` and the six `2026-09-11-*` / `2026-09-13-*` entries.
  - `hooks/hooks.json`.
- **Checked against:**
  - `scripts/lib/resolve.sh`, `scripts/lib/index-sync.sh`,
    `scripts/lib/index-compose.sh` and `scripts/resolve.sh`;
  - `scripts/cc-hooks/`: `relay-drain.sh`, `session-start.sh`,
    `index-sync-post.sh`, `index-compose.sh` and `add-tier-batch.sh`;
  - `relay-redesign.md` §Docs and the outline's §Design record.
- **Excluded:** `CLAUDE.md`, `testing.md`, `README.md` and the 2026-09-07
  entries.
- **Read-only:** no repo file was edited apart from this report.

## Prior findings status

Prior prose report, at HEAD:

- **M1 / review M5, the D50 invariant against the take path — resolved.**
  - `gitlore_adopt_tier_into_root` now returns 1 before any staging when
    `gitlore_compose_up` fails.
  - `compose_merged_indexes` returns 1 without staging root, and the
    continuation skips the gitlink staging.
  - `git-hooks.md` and `tier-stores.md` agree. A qualification gap remains; see
    m3.
- **M2, the `CLAUDE.md` gate paragraph — out of this partition.** It is an open
  decision.
- **m1, the `pre-commit` step list — resolved.** It is in execution order and
  includes the tier sync. Merging steps 3 and 4 broke a step reference; see
  Major M1.
- **m2, the changelog sequence skipping the tier sync — resolved.** It now reads
  "compose → tier commits → add -A".
- **m3, "sixth untracked file" — resolved.** No "sixth" is left in `docs/` or
  `scripts/`.
- **m4, the relay write contract missing from the node — resolved.** The relay
  block records the atomic install, the `.tmp` rule and both residuals, and
  `configuration.md` lists the relay files. A list gap remains; see m8.
- **m5, argued alternatives not named — partly resolved.** They are named in
  `decisions.md`, and D50's line carries "dirty store". Three names have no
  entry in their node's `## Rejected alternatives` section; see m5.
- **m6, "all four" — resolved.** The four attachment kinds are enumerated.
- **m7, `session.md` steps 6 and 10 — resolved.** Both arms of step 6 end the
  pass, matching `session-start.sh:199-212`.
- **m8, recovered-merge adoption covering only the checkout case — resolved.**
  The text now reads "Whether HEAD already carries the merge or is put back onto
  it".
- **m9, the hub not mentioning the relay — resolved.** The hooks bullet names
  the relay drainer and D51.
- **m10, D51 linking to an unheaded paragraph — resolved.** The relay is a
  titled block, **The relay — D51's mechanism**, named in the node's header
  list.
- **m11, `CLAUDE.md` citing `plans/` — out of this partition.** No `plans/<job>`
  citation is left in `CLAUDE.md`.

## Critical

None.

## Major

### M1 — the gitlink invariant cites a step that no longer exists

- **Where:** `docs/references/git-hooks.md:81-82`.
- **Axes:** usability (broken reference), accuracy.
- **Doc:** "`pre-commit` makes it `live` itself: step 5 stages the commit step 4
  just advanced `live` to."
- **The list it points at:** it now has four steps. Line 50 is "3.
  **Sync memory** … then `push . HEAD:live` fast-forward-only", and line 63 is
  "4. **Stage the gitlink** into the index git handed the hook".
- **Cause:** the minor pass (item 1) merged the old steps 3 and 4 and renumbered
  step 5 to 4. It did not update this sentence.
- **Consequence:**
  - "step 5" names nothing.
  - "step 4" names the staging step, not the advance.
  - The sentence is the one-line proof of the invariant that NFR5 and D46 rest
    on, and a reader checking it against the list finds it wrong.
- **Fix:** "step 4 stages the commit step 3 just advanced `live` to".

## Minor

### m1 — "every later failure restamps it" has two non-restamping returns

- **Where:** `docs/references/git-hooks.md:162-168`.
- **Axis:** accuracy.
- **Doc:** "A failure keeps the approval, unless it prepared a merge. … So every
  later failure restamps it."
- **First counter-example:** the tier guard loop in
  `gitlore_sync_memory_to_live`.
  - The code is `gitlore_guard_stale_merge_state "$mempath/$tier" || return 1`,
    with no `touch`.
  - That guard also returns 1 without preparing anything: the
    `orphaned-merge-head` arm ("holds a merge gitlore did not prepare … nothing
    was changed"), and `gitlore_recover_landed_merge`'s "HEAD could not be put
    back" arm.
  - An earlier tier in the same loop may already have written the up projection
    the doc names ("a recovered merge's up projection").
- **Second counter-example:** `gitlore_sync_tiers_to_live`.
  - When a non-fast-forward refusal does not classify as diverged, the code runs
    `elif gitlore_check_head_live_agree …; then … fi; return 1`, also with no
    `touch`.
  - By then the compose has already written carriers.
- **Reachability:** both need two tiers or a race.
- **Note:** the code comment above the tier loop makes the same classification
  ("the stale-merge guard in this loop … return without one"). The fix may
  belong on the code side. Otherwise, narrow the sentence.

### m2 — the drainer is called the only reader; `SessionStart` drains too

- **Where:**
  - `docs/references/index-authoring-sync.md:132`: "`relay-drain.sh` is the only
    hook that reads a report."
  - `docs/design.md:214`: "a `PostToolBatch` relay drainer is the one consumer
    of the reports".
  - Changelog `2026-09-13-the-relay-is-one-file-per-report.md:34`: "is new and
    is the only consumer".
- **Axes:** accuracy, consistency.
- **Code:** `scripts/cc-hooks/session-start.sh:418` runs
  `gitlore_relay_drain "$mempath" "$session"`. The node's own paragraph at line
  156 says "`SessionStart` drains the same session".
- **Why Minor:** both drainers call the one library function, so the
  misstatement hides no divergent behaviour. `relay-redesign.md` and D51's
  conclusion line say the precise thing: "the only PostToolBatch consumer",
  "drained by a dedicated `PostToolBatch` hook".
- **Also:** the same wording is in the comments at `index-compose.sh:79` and
  `index-sync-post.sh:257`, which are outside this partition.

### m3 — D50's adoption invariant is stated more broadly than the code

- **First statement:** `docs/references/git-hooks.md:192-194`.
  - **Doc:** "A take and a landed merge continuation that stage nothing also
    return the tier to its pin".
  - **Code:** `rest_unadopted_tier` in `scripts/resolve.sh` has an arm that
    returns without a checkout: "tier '$tier' stays on the merge commit: the
    commit the memory store records for it is not one the merge contains".
  - **Code:** the yield arms (`gitlore_yield_merge … || exit 1; exit 1`) exit
    before `rest_unadopted_tier`.
  - `tier-stores.md:176-179` states both exceptions, so the sentence here needs
    "on the paths that exit 0".
- **Second statement:** `docs/references/merge-state-recovery.md:84-85`.
  - **Doc:** "the one shape in which a tier ahead of its pin may be adopted
    (D43)".
  - `git-hooks.md:194-196` states an exception: "The one exception is a tier
    commit the commit path itself made".
  - **Code:** `gitlore_stage_landed_tiers` stages the gitlink alone
    (`add -- "$tier"`).
  - The two nodes disagree. The "one shape" claim is also D50's rule, not D43's.
- **Also in `merge-state-recovery.md:88`:** "A failed up projection therefore
  stages nothing" follows the no-op sentence that was inserted before it, so
  "therefore" no longer points at its reason, the staging hazard.

### m4 — the unadopted tier merge "publishes" unconditionally

- **Where:** `docs/references/tier-stores.md:171-172`, with the same claim in
  changelog `2026-09-13-a-tier-merge-…:12-13`.
- **Axis:** accuracy.
- **Doc:** "The continuation commits the merge in the tier, clears the merge
  state, advances `live` and publishes".
- **Code:** in `scripts/resolve.sh`, the continuation exits early on
  `if [ "$publish" = "no" ]; then … exit 0`. It pushes to origin only under
  `if [ "$flavor" = "head-vs-remote" ]`.
- **Consequence:** every merge `/gitlore:merge` prepares is marked no-publish.
  The take-side case this paragraph describes is therefore exactly the one that
  does not publish.

### m5 — named rejected alternatives with no entry in the node's section

- **Axis:** conformance. `design.md` says a rejected alternative is "argued in
  the `## Rejected alternatives` section that closes the group's node".
- **`docs/decisions.md`, git-hooks group:**
  - "composing a clean store" is argued only inside D50's body
    (`git-hooks.md:140`, "**Dirty stores only.**").
  - "reporting a non-empty commit-path compose" is argued only inside D50's body
    (`git-hooks.md:198`, "**A successful compose here stays silent**").
  - `git-hooks.md:205-228` has neither.
- **`docs/decisions.md`, D51 group:** "relaying in place of the subagent's own
  emission" is argued only in `index-authoring-sync.md:110-112`.
  `cc-platform.md`'s Rejected section has no entry for it.
- **Unnamed alternative:** "staging nothing without the walk-back" on a failed
  take — leaving the tier ahead of an unstaged pin.
  - It is argued in `tier-stores.md:163-165`: "Leaving the tier ahead of an
    unstaged pin instead has the pin guard refuse every commit".
  - It is weighed in changelog `2026-09-13-a-take-…:19-27`.
  - No *Rejected* line in `decisions.md` names it.

### m6 — "a report shares the pre-image's key"

- **Where:** `docs/references/index-authoring-sync.md:113`.
- **Axis:** accuracy, left over from the per-agent design.
- **Doc:** "A report therefore shares the pre-image's key and not its consumer".
- **Code:** the pre-image path is
  `gitlore-index-preimage$(_gitlore_agent_suffix "${2:-}")`, keyed by agent
  alone. The relay name is `gitlore-relay-$s-$a-$epoch-$pid-$tag`, keyed by
  session and agent. The next paragraph states the relay name correctly.

### m7 — the pin rule's callers are under-enumerated

- **Where:** `docs/references/index-composition.md:103-105`.
- **Axis:** accuracy, clarity.
- **Doc:** "only the down-projecting passes run it — the in-session one and the
  commit path".
- **Code:** `gitlore_compose` itself runs
  `gitlore_compose_check_pins "$mempath" || refused=1`. That covers
  `session-start.sh`, `index-compose.sh` and `add-tier-batch.sh`, plus the
  commit path's own pre-check.
- **Consequence:** the singular "the in-session one" reads as the
  `PostToolBatch` pass. The Down bullet in the same node (line 232) lists three
  down passes: `PostToolBatch`, `SessionStart` and the commit path.

### m8 — `configuration.md`'s gitdir state list

- **Where:** `docs/references/configuration.md:43-48`.
- **Axes:** completeness, accuracy.
- **Missing files:** the list now carries `gitlore-tier-landing` and the relay
  files. It still omits `gitlore-index-preimage[-<agent>]` and
  `gitlore-compose-stamp[-<agent>]`. These are hook-owned gitdir state whose
  names this plan changed (FR-C), and the same holds for the budget and upgrade
  nudge files.
- **Wrong wording:** "removed by the drain that folds it into the parent's own
  report" does not fit `relay-drain.sh`, which has no report of its own. It
  emits only `GITLORE_RELAY_SYSMSG` and `GITLORE_RELAY_CTX`. Only `SessionStart`
  folds reports into its own output.

### m9 — the hub bullet links neither D51's node nor the per-agent keying

- **Where:** `docs/design.md:209-221`.
- **Axis:** usability.
- **Doc:** the bullet adds "per agent so a parent batch cannot consume a
  subagent's baseline" and the relay drainer (D51). Its links remain
  "[session.md]; the nudge in [commit-gate.md], the index pair in
  [index-composition.md]".
- **Where the content lives:** the keying and the relay mechanism are in
  `index-authoring-sync.md`, and D51 is in `cc-platform.md`. Neither is linked
  from the bullet.

### m10 — the changelog list switches from tight to loose

- **Where:** `docs/changelog.md:15,21,28,36`.
- **Axis:** style.
- **Problem:** the four 2026-09-13 bullets are separated by blank lines. Every
  other bullet in the file, including both 2026-09-11 entries directly below, is
  tight. In CommonMark one blank line makes the whole list loose, so every entry
  renders as a paragraph.

## Checks that passed

- **Docs graph:** `python3 scripts/check-docs-links.py` exits 0 with every
  counter at zero: broken-link, unstubbed-decision, stub-without-body,
  duplicate-decision, duplicate-conclusion, undefined-decision,
  enumeration-drift, delegation-drift and oversized-file.
- **Size and wrap:**
  - Every changed doc is under 400 lines. The largest are `session.md` at 392
    and `index-authoring-sync.md` at 374.
  - No prose line in a changed doc exceeds 80 characters, counted in characters
    and not bytes. The only overruns are link-only bullet lines in
    `changelog.md`.
- **Tense:** added lines in `docs/references`, `design.md` and `decisions.md`
  carry no "now", "no longer" or "previously" correction framing. Changelog
  entries are history, as they should be.
- **Old node name:** no live reference to `git-hooks-and-entry-points` outside
  `plans/`, dated changelog entries and `.claude/handoff-todo.md`.
- **`relay-redesign.md` §Docs, every item landed:**
  - `index-authoring-sync.md` has the titled relay block, named in the header
    list. It covers the atomic install, the occupied-name refusal, the `.tmp`
    drain rule and its residual, and the delivery-timing and drain-to-emit
    residuals.
  - `cc-platform.md` D51 has the "keyed by session and agent, drained by a
    dedicated `PostToolBatch` hook" sentence, with its pointer.
  - `session.md` step 10 covers the own-session drain and the age sweep.
  - D51's line in `decisions.md` names all four redesign rejections.
  - The hub bullet names the drainer.
  - `configuration.md` lists the relay files.
  - `changelog.md` has the entry.
  - The old-premise comments are gone: no "sequential" or "merged into, not
    truncated" left in the relay code.
- **Relay claims verified against code:**
  - The name `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>`, with `nosession` when
    there is no session id, the closed tag set and `${BASHPID:-$$}`.
  - Built at `.tmp`, installed by `mv`, and an existing name refused with the
    temp removed.
  - The drain uses `find -type f … '!' -name '*.tmp'`, sorts `LC_ALL=C`,
    recovers the agent as `${rest%-*-*-*}`, frames both channels and removes
    only what it read.
  - The sweep is `-mtime +7`, temps included.
  - `relay-drain.sh` parses its payload first, exits at once on a keyed run, and
    needs no baseline.
  - A failed write appends to `additionalContext`, with the `$sysmsg` fallback
    in the sync hook.
  - `session-start.sh` drains after the diverged and failed-fast-forward exits.
- **The same probe, cited consistently:** `index-authoring-sync.md`,
  `cc-platform.md`, `session.md`, `design.md`, `decisions.md` and the changelog
  agree on D51 in substance, apart from m2. The parent `session_id` measurement
  and CC 2.1.261 are cited the same way in every one.
- **`hooks/hooks.json`:** `relay-drain.sh` is registered as its own
  `PostToolBatch` group with no matcher, beside the five existing groups. The
  script exists and is executable (`-rwxr-xr-x`). The JSON parses.
- **D50 claims verified against `gitlore_sync_memory_to_live`:**
  - The order: memory guard, freshness gate, tier guards, then
    `gitlore_stage_landed_tiers`, the pin guard (abort, restamp, no remedy of
    its own), compose (rc 1 reports; rc 2 and unknown abort and restamp),
    `gitlore_sync_tiers_to_live`, `add -A`, landing-record removal, the commit,
    and `push . HEAD:live`.
  - The landing record is written before each tier commit, removed on a failed
    commit and after `add -A`, and matched on HEAD's parent and the index pin.
  - The pin is read from the index (`:$tier`).
- **The D50 invariant across nodes** (`git-hooks.md`, `tier-stores.md`,
  `merge-state-recovery.md`): up first, then stage the pair, or stage nothing.
  It holds in:
  - `gitlore_adopt_recovered_merge`, including the already-adopted short-circuit
    (`[ "$tier_head" = "$pinned" ] && return 0`);
  - `gitlore_adopt_tier_into_root`, which walks the tier back and returns 1;
  - the continuation, which skips the staging when `tier_unadopted`.

  The exceptions and wording are in m3.
- **Remedy claims:** the next `/gitlore:resolve` names `/gitlore:merge` for a
  tier whose `live` is ahead (`gitlore_check_head_live_agree`). The adoption
  remedies quote their paths (`resolve.sh:356`, `:1799`).
- **Decision records:**
  - D50 and D51 each have one conclusion line.
  - Node heading, header bullet, `decisions.md` line and hub clause agree.
  - The node titles enumerate `git-hooks.md` (D46, D50) and `cc-platform.md`
    (D15, D18, D23, D51).
- **Changelog:**
  - Both surfaces are present for all six entries.
  - Bullets run newest-first and match commit order within each day.
  - Every entry is titled with its decision.
- **Outline §Design record:** the D50 decision, its dirty-only scope, the
  refusal asymmetry, the "instructs the agent to run compose" rejection, the hub
  bullet and the changelog are all present.
