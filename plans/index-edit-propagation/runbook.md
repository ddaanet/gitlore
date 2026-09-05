# Runbook — index-edit propagation

Design: `outline.md` (this directory). Triage in `classification.md`; the
evidence settling findings 2 and 3 in `root-cause.md`; the subagent-confinement
probe in `subagent-hook-output-probe.md`.

Change A of the outline is applied (`c0963f5`). This runbook covers B, C, D and
the design record.

## Requirements

Local IDs, each tracing to a `docs/design.md` requirement.

| Requirement | Traces | Phase | Items | Notes |
|---|---|---|---|---|
| FR-B — a memory commit never records a carrier stale against the root index | FR15, FR8, NFR5 | 1 | 1.1 | outline §B |
| FR-C — parent and subagent batches never consume each other's index baselines | FR15, FR2 | 2 | 2.1 | outline §C |
| FR-D — compose and index-sync reports produced inside a subagent reach the parent session | NFR2, NFR4 | 3 | 3.1 | outline §D; depends on FR-C |
| FR-E — the design record carries the commit-path composition decision | project convention (`CLAUDE.md` §Writing) | 4 | 4.1, 4.2, 4.3 | outline §Design record |

Out of scope, per the outline: finding 2 (no defect), a dirty-carrier query
surface, backfilling descriptions that never matched their index lines.

## Corrections to the outline

- **Test home for FR-B.** The outline names
  `tests/git_hook_memory_pre_commit.bats`. That suite has three cases and its
  SUT is `scripts/git-hooks/memory-pre-commit` — the memory submodule's FR11
  sentinel gate, not the parent hook. The parent `pre-commit` hook's suite is
  `tests/git_hook_pre_commit.bats` (13 cases, `HOOK=.../git-hooks/pre-commit`),
  and `tests/integration_gitlink_staging.bats` is where a real `git commit`
  drives it in all three index modes. Phase 1 uses those two.
- **`docs/design.md` line cap.** The cap is `MAX_LINES = 400` in
  `scripts/check-docs-links.py:55`, enforced by `check_size` over every file
  under `docs/` and blocking as `oversized-file`. Item 4.2 states the decision
  taken; see its note.

---

## Phase 1: Compose in the commit path (type: tdd)

- Item 1.1: `scripts/lib/resolve.sh` — `gitlore_sync_memory_to_live` composes
  the store before it commits, inside the `dirty = 1` branch, after the
  freshness check and before `gitlore_sync_tiers_to_live`. Requirements: FR-B.
  Model: opus

  The one edit reaches both entry points: `scripts/git-hooks/pre-commit:68` and
  `scripts/commit-memory.sh:66` both call this function and nothing else. The
  library already sources `index-compose.sh` (`scripts/lib/resolve.sh:11`), so
  `gitlore_compose` is in scope with no new dependency.

  Reporting is `gitlore_say_for_agent_or_user`, redirected to stderr, matching
  every other call to that helper in this file. Not
  `gitlore_compose_and_report`, whose product is `PostToolBatch` JSON in
  `GITLORE_COMPOSE_SYSMSG`/`GITLORE_COMPOSE_CTX` and is meaningless to git.

  Test-suite note: `tests/commit_memory.bats` currently loads `helpers/setup`,
  `helpers/fixtures`, `helpers/divergence-fixtures`;
  `tests/git_hook_pre_commit.bats` loads the same three. Both need
  `load helpers/tier-fixtures` for `make_tier_in_memory` / `set_tier_manifest` /
  `seed_tier_bullet`. That load line rides slice 1 rather than a setup-only
  item.

  Slices:

  1. **External contract — the committed carrier is the composed one.** Fixture,
     shared by both tests: `make_parent_with_memory`,
     `make_tier_in_memory ddaanet`, `set_tier_manifest ddaanet`, then a root
     index bullet `- [shared](ddaanet/shared.md) — fresh hook` (via
     `seed_root_bullet`) while the tier's own carrier at
     `memory/ddaanet/MEMORY.md` carries the same path under `stale hook`, and
     the file `memory/ddaanet/shared.md` exists. An approved summary is written
     to `gitlore_commit_msg_file`.
     - `commit-memory composes the carrier into the commit it makes` in
       `tests/commit_memory.bats` — runs
       `scripts/commit-memory.sh -m <summary>`; asserts
       `git -C memory/ddaanet show HEAD:MEMORY.md` contains `— fresh hook` and
       does not contain `stale hook`.
     - `the parent pre-commit hook composes the carrier before committing` in
       `tests/git_hook_pre_commit.bats` — runs `bash "$HOOK"`; asserts the same
       two conditions on the tier's committed `HEAD:MEMORY.md`.

     Both must fail against unchanged code on that assertion, not on a missing
     symbol: `gitlore_sync_memory_to_live` already exists and already commits,
     so the red is the committed carrier still reading `stale hook`.

  2. **Ordering — the memory commit pins the post-compose tier SHA.** Compose
     writes into `memory/<tier>/MEMORY.md`, so it must precede
     `gitlore_sync_tiers_to_live`; placed after it, the tier commit would not
     contain the composed carrier and memory's gitlink would pin the pre-compose
     tree. Same fixture as slice 1.
     - `the memory commit records the tier SHA that carries the composed carrier`
       in `tests/commit_memory.bats` — asserts
       `git -C memory rev-parse HEAD:ddaanet` equals
       `git -C memory/ddaanet rev-parse HEAD`, and that the blob at
       `git -C memory/ddaanet show HEAD:MEMORY.md` contains `— fresh hook`. The
       pair is what makes it non-vacuous: the SHA equality alone passes when
       neither composed.

  3. **Dirty-only scope — a clean store is not composed.** Composing a clean
     store creates a dirty state no approved summary covers, and the FR11 gate
     would then refuse a commit for a change the agent never made. Fixture: the
     slice-1 divergence *committed* on both sides — root index carrying
     `fresh hook`, tier carrier carrying `stale hook`, both committed, working
     tree clean, and no `gitlore_commit_msg_file` present.
     - `a clean store is not composed by the commit path` in
       `tests/git_hook_pre_commit.bats` — runs `bash "$HOOK"`; asserts exit 0,
       that `memory/ddaanet/MEMORY.md` on disk still contains `stale hook`, that
       `gitlore_memory_dirty memory` is still `0`, and that
       `git -C memory rev-parse HEAD` is unchanged from before the run. The
       dirty-state assertion is the one that discriminates: without the
       `dirty = 1` guard the file changes and the store goes dirty.

  4. **An off-pin refusal is reported and the commit proceeds.**
     `gitlore_compose` returns 1 when `gitlore_compose_check` or
     `gitlore_compose_check_pins` refuses, having written nothing (D31, D36):
     projecting root's older text over an unadopted carrier would destroy
     approved upstream facts, so committing the carrier as-is is correct.
     Induction: an active, materialized tier whose worktree `HEAD` differs from
     the gitlink recorded in the memory store's **index** — reach it with a
     commit inside `memory/ddaanet` that is never `git -C memory add`-ed. The
     tier must not be mid-merge, or `gitlore_compose_check_pins` emits its other
     message instead. Memory is otherwise dirty with a fresh approved summary,
     so the commit is reached.
     - `an off-pin compose refusal is reported and does not abort the commit` in
       `tests/commit_memory.bats`, run with `--separate-stderr` — asserts exit
       0, that `git -C memory rev-parse HEAD` advanced past its pre-run value,
       and that `$stderr` contains `refused`. Exit-code-only would pass against
       unchanged code; the stderr string is what proves the refusal was
       surfaced.

  5. **A write failure aborts the commit.** `gitlore_compose` returns 2 when
     `gitlore_compose_write` fails partway, leaving the store partly composed; a
     half-written carrier must not be committed. Reuse the induction proven at
     `tests/index_compose.bats:920` — `chmod a-w memory/ddaanet` so the temp
     file cannot be created in the carrier's directory — restoring `chmod u+w`
     immediately after `run`, and guarding with
     `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"`, the guard
     `tests/index_sync.bats:356` carries and the existing compose case lacks.
     - `a compose write failure aborts the commit` in `tests/commit_memory.bats`
       — asserts non-zero exit, that `git -C memory rev-parse HEAD` is
       unchanged, and that the approved `gitlore_commit_msg_file` still exists
       (the abort must not consume it, or the retry loses the user's approval).

---

## Phase 2: Per-agent index baselines (type: tdd)

- Item 2.1: `scripts/lib/index-sync.sh` plus its four consumers — key the
  pre-image and compose-stamp paths on the hook payload's `agent_id`.
  Requirements: FR-C. Model: opus

  `gitlore_index_preimage_file` (`scripts/lib/index-sync.sh:94`) and
  `gitlore_compose_stamp_file` (`:102`) each return one fixed
  `rev-parse --git-path` name. Parent and subagent batches share them,
  `index-sync-pre.sh:48,53` skips re-baselining when a file is already present,
  and every consumer `rm -f`s unconditionally — so a parent batch ending between
  a subagent's pre-hook and its post-hook consumes the subagent's baseline and
  strands its edit silently.

  Both helpers take a second, optional argument: the agent id. Empty or absent
  yields today's unsuffixed name, which stays the main thread's, so nothing
  migrates. Non-empty appends `-<agent_id>`.

  Read `agent_id`, never `agent_type`: `agent_id` is present only when the hook
  fires from within a subagent, while `agent_type` also appears on the main
  thread of an `--agent` session (`memory/ddaanet/hook-input-schema.md`). The
  string `agent_id` appears nowhere under `scripts/` today, so each of the four
  consumers gains a new `jq -r '.agent_id // empty'` read of a payload it
  already has in hand:

  - `scripts/cc-hooks/index-sync-pre.sh:40-41` — already holds `$payload`.
  - `scripts/cc-hooks/index-sync-post.sh:30` — already holds `$payload`.
  - `scripts/cc-hooks/index-compose.sh:32` — currently `cat >/dev/null` at line
    23 to drain the payload; it must capture it instead and read `agent_id` from
    it. The comment at lines 18-23 saying the stamp and not the payload's
    contents is the signal stays true of the *trigger*; it needs the qualifier
    that the payload is now also read for the agent id.
  - `scripts/cc-hooks/add-tier-batch.sh:75` — drops the compose hook's baseline;
    that drop must target the same keyed path.

  `scripts/cc-hooks/index-sync-pre.sh:43-47` carries the comment this change
  falsifies — "Each post hook removes its own file at batch end (even when
  nothing was touched), so an existing one here always belongs to the batch in
  flight." That is the invalidated assumption itself: rewrite it to say the
  baselines are keyed per agent, so an existing one belongs to the batch in
  flight *of this agent*.

  Bound the stranded-file residual in a comment rather than adding a sweeper,
  the way `index-sync-post.sh:36-38` already bounds a stale pre-image: a
  subagent that dies mid-batch strands a keyed file, and that file is consumed
  and deleted by the next batch of the same agent id — an agent id is not
  reused, so the bound is one file per dead subagent, not unbounded growth.

  Slices:

  1. **External contract — the helpers key on the argument.**
     - `preimage_file is unsuffixed with no agent id` in `tests/index_sync.bats`
       — asserts `gitlore_index_preimage_file memory` and
       `gitlore_index_preimage_file memory ""` both end in
       `gitlore-index-preimage` with no trailing hyphen.
     - `preimage_file suffixes the agent id` — asserts
       `gitlore_index_preimage_file memory agent-7` ends in
       `gitlore-index-preimage-agent-7`.
     - `compose_stamp_file is unsuffixed with no agent id` and
       `compose_stamp_file suffixes the agent id` — the same two assertions
       against `gitlore-compose-stamp`.

  2. **The pre-hook writes to the keyed path.**
     - `pre: a payload carrying agent_id stamps the keyed path, not the bare one`
       in `tests/index_sync.bats` — drives `index-sync-pre.sh` with an `Edit`
       payload naming `memory/MEMORY.md` and `agent_id: "a1"`; asserts
       `[ -f "$(gitlore_compose_stamp_file memory a1)" ]`,
       `[ -f "$(gitlore_index_preimage_file memory a1)" ]`, and that neither
       unsuffixed path exists.
     - `pre: a payload with no agent_id stamps the bare path` — same drive
       without the field; asserts both unsuffixed paths exist and no file
       matching the keyed glob does.

  3. **A parent batch does not consume a subagent's baseline.** This is the race
     the item exists to close, driven end to end.
     - `a parent post-hook leaves a subagent's pre-image intact` in
       `tests/index_sync.bats` — pre-hook with `agent_id: "a1"`, then a root
       index edit, then `index-sync-post.sh` with **no** `agent_id`; asserts the
       keyed pre-image still exists after the parent's post-hook ran, and that
       the parent's post-hook emitted no output (it had no baseline of its own,
       so nothing to diff).
     - `the subagent's own post-hook then consumes its keyed pre-image` — the
       continuation: `index-sync-post.sh` with `agent_id: "a1"` propagates the
       edited hook into the named file's `description:` and removes the keyed
       pre-image.

  4. **The same keying holds for the compose hook.**
     - `a main-thread compose baseline survives a subagent's compose hook` in
       `tests/cc_hook_index_compose.bats` — pre-hook with no `agent_id`
       establishing the bare stamp, then `index-compose.sh` driven with
       `agent_id: "a1"`; asserts the bare stamp file still exists and the run
       emitted nothing. The suite's `pre()` and `feed()` helpers take an
       optional agent id for this.
     - `add-tier-batch drops the compose baseline for its own agent` — asserts
       that with `agent_id: "a1"` on the batch payload, `add-tier-batch.sh`
       removes `gitlore_compose_stamp_file memory a1` and leaves an
       independently-created bare stamp in place.

---

## Phase 3: Relay a subagent's reports to the parent (type: tdd)

- Item 3.1: `scripts/lib/index-sync.sh` and three hooks — a hook firing inside a
  subagent writes its report to a keyed marker; the next parent-side run folds
  the markers into its own report and removes them. Requirements: FR-D. Depends
  on: Item 2.1 Model: opus

  Settled empirically, not assumed: a hook firing inside a subagent has both its
  `systemMessage` and its `hookSpecificOutput.additionalContext` confined to
  that subagent — the parent transcript carries zero `hook_*` attachments while
  the subagent's own JSONL carries all four, and the no-subagent control
  surfaces both channels normally (`subagent-hook-output-probe.md`, CC 2.1.261).
  So a subagent's edit to the root index composes, and the report reaches
  neither the parent's context nor the user.

  The marker is a sixth untracked `rev-parse --git-path gitlore-…` file in the
  memory gitdir, beside `gitlore-nudged` (`scripts/lib/util.sh:163`),
  `gitlore-merge-state` (`:217`), `gitlore-index-preimage` and
  `gitlore-compose-stamp`. One helper serves both reports: the confinement is a
  property of the event, not of the script.

  Each folded-in block is attributed to its agent, so an interleaved session
  stays legible — one line of framing per block.

  In addition to, not instead of: the subagent still emits its own report. It is
  the actor, and a blind agent goes looking rather than waiting — measured at
  re-verification after 91% of silent commits, against 35% where the outcome
  came back inside a tool result (`memory/ddaanet/hook-output-channels.md` §6).
  Suppressing the subagent's copy buys nothing and costs the actor its
  confirmation.

  `scripts/cc-hooks/session-start.sh` drains the same markers (its compose runs
  at `:325-338` and it accumulates user-facing text through `add_sysmsg`), so a
  marker outliving its session is not lost.

  Interfaces:
  - `gitlore_relay_marker_file <mempath> [<agent_id>]` → prints the absolute
    path of the relay marker; unsuffixed when the agent id is empty or absent
  - `gitlore_relay_write <mempath> <agent_id> <sysmsg> <ctx>` → returns 0 after
    writing the two report bodies to the keyed marker; returns non-zero without
    writing when the marker cannot be created
  - `gitlore_relay_drain <mempath>` → prints the accumulated relayed blocks,
    each prefixed with its agent id, and removes every keyed marker; prints
    nothing and returns 0 when no marker exists

  Slices:

  1. **External contract — write keyed, drain unkeyed.**
     - `relay_marker_file suffixes the agent id` in `tests/index_sync.bats` —
       asserts `gitlore_relay_marker_file memory a1` ends in `-a1` and
       `gitlore_relay_marker_file memory` does not.
     - `relay_write then relay_drain returns the block and removes the marker` —
       writes a sysmsg `S1` and ctx `C1` under `a1`, drains, asserts the output
       contains `S1`, `C1` and the literal `a1`, and that
       `gitlore_relay_marker_file memory a1` no longer exists.
     - `relay_drain on an empty store prints nothing and returns 0` — asserts
       empty output and status 0.

  2. **The compose hook relays instead of reporting, when keyed.**
     - `a keyed compose run writes a marker and emits no parent-facing json` in
       `tests/cc_hook_index_compose.bats` — pre-hook and compose hook both with
       `agent_id: "a1"` over a root index edit that composes; asserts the run's
       stdout is still valid JSON carrying the compose `systemMessage` (the
       subagent gets its own copy) **and** that
       `gitlore_relay_marker_file memory a1` exists and contains the same
       `recomposed tier pointers` text.
     - `an unkeyed compose run folds in the marker and removes it` — with that
       marker in place, an unkeyed compose run over an index edit; asserts its
       `systemMessage` carries both its own `recomposed tier pointers` line and
       the relayed block, that the block is attributed to `a1`, and that the
       marker file is gone.

  3. **The same relay carries the index-sync report.**
     - `a keyed index-sync run writes its replacement report to a marker` in
       `tests/index_sync.bats` — pre- and post-hook with `agent_id: "a1"` over
       an index line whose hook changed; asserts the keyed marker contains the
       `reset frontmatter to match MEMORY.md` line and the `• <path>:` bullet.
     - `an unkeyed index-sync run folds in the marker` — asserts the unkeyed
       post-hook's `systemMessage` carries the relayed block attributed to `a1`
       and the marker is removed.

  4. **SessionStart drains a marker that outlived its session.**
     - `session-start drains a stranded relay marker` in
       `tests/cc_hook_index_compose.bats` — writes a marker under `a1` directly,
       runs `scripts/cc-hooks/session-start.sh`; asserts its `systemMessage`
       carries the relayed text attributed to `a1` and the marker file is gone.
     - `session-start with no marker is unchanged` — the negative that keeps the
       positive honest: asserts the SessionStart output contains no attribution
       framing when no marker exists.

  5. **A marker that cannot be written does not lose the report.**
     - `a failed relay write leaves the subagent's own report intact` in
       `tests/cc_hook_index_compose.bats`, guarded with
       `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"` —
       `chmod a-w` on the memory gitdir so the marker cannot be created,
       restored immediately after `run`; asserts the hook still exits 0 and its
       own `systemMessage` still carries the compose report. A hook that aborted
       here would trade a relay failure for a total one.

---

## Phase 4: Design record and changelog (type: general)

- Item 4.1: `docs/references/git-hooks-and-entry-points.md` — record the
  commit-path composition decision as a new numbered decision with its rejected
  alternative. Requirements: FR-E. Depends on: Item 1.1 Model: opus

  The node is 340 lines, so the addition stays under the 400-line cap. Take the
  next free `D<n>` — `scripts/check-docs-links.py` blocks a `duplicate-decision`
  and an `undefined-decision`, so the number must be new and must be argued here
  and concluded once in the hub (Item 4.2).

  The decision states: the commit path composes before it commits, scoped to
  `dirty = 1` only, with a refusal reported and not fatal and a write failure
  aborting. Its argument carries the three reasons Phase 1 encodes — the carrier
  is what the tier's remote receives, so a stale one *ships*; composing a clean
  store manufactures a dirty state no approved summary covers, which is what
  keeps the FR11 boundary intact; and an off-pin refusal is correct to commit
  through, because projecting root's older text over an unadopted carrier would
  destroy approved upstream facts.

  Its `Rejected:` line takes
  **a refusal that instructs the agent to run compose** — rejected because
  composition needs no judgement, so making the agent run it is overhead the
  harness should absorb (NFR4).

- Item 4.2: `docs/design.md` — conclude the new decision in the hub, and resolve
  the hub's line budget. Requirements: FR-E. Depends on: Item 4.1 Model: opus

  Two edits, both in one item because they are edits to one prose artifact:

  - §Architecture, the **Git hooks and entry points** bullet (lines 218-228) —
    one clause added to the existing sentence about `pre-commit`, saying it
    composes the store before committing so the carrier a tier's remote receives
    matches the root index.
  - §Design Decisions, the **Git hooks and entry points** block (lines 308-318)
    — one `- **D<n>** — …` conclusion stub beside D16/D20/D46, and the rejected
    alternative appended to the block's existing `*Rejected:*` line.

  **Line budget.** `docs/design.md` is at exactly 400 lines and
  `scripts/check-docs-links.py:55` caps every file under `docs/` at 400, so
  these ~4 lines block the build as `oversized-file`. Resolution taken: give the
  **hub** its own cap, separate from the node cap, and raise it to 440.

  The rationale is recorded in `check-docs-links.py`'s own module docstring
  (lines 29-31) beside the existing cap note: the 400-line cap exists because a
  node has to be readable in one go on a reader's node budget, and that argument
  does not transfer to the hub, which is read whole as the entry point rather
  than as one node among many. The hub has already been through four split
  passes; what remains is the six-section living-doc skeleton, where per-section
  return on a further cut is near 1:1 — and a 1:1 ratio means the material was
  never separable, not that the document has run out of room.

  Implementation: a `HUB_MAX_LINES = 440` constant read by `check_size` when the
  path is the hub, `MAX_LINES = 400` for every other file, and a case in
  `tests/check_docs_links.bats` beside the existing 400-line filler case
  (`:374`) asserting the hub path passes at 440 lines and blocks at 441 while a
  node still blocks at 401.

  **This resolution is the one open decision in the runbook.** The outline put
  it to my human partner as the split-versus-overage fork and it is stated here
  as a default so the runbook is executable; an instruction to split
  `docs/design.md` instead replaces this item's second half and adds a phase.

- Item 4.3:
  `docs/changelog/2026-09-06-the-commit-path-composes-before-it-commits.md` and
  `docs/changelog.md` — the changelog's two required surfaces. Requirements:
  FR-E. Depends on: Item 4.2 Model: sonnet

  An entry file under `docs/changelog/` carrying what changed and why, and its
  newest-first summary bullet at the top of `docs/changelog.md`.
  Design-significant only: the commit-path composition decision and the
  per-agent keying that made the subagent relay possible; not the test counts.

---

## Gate

`just precommit` outruns the Bash tool's 10-minute cap and is killed before it
records its sentinel, so run `just lint`, `just test-integration` and
`just test-unit` as three sequential calls and say that the sentinel was not
recorded. `just format-docs` (precommit's first step) hard-wraps `docs/` and
`plans/`, so run it before measuring `docs/design.md` against the cap in Item
4.2 — the line count only means anything after the wrap.

Phase 4 also needs `python3 scripts/check-docs-links.py`, which is what enforces
`duplicate-decision`, `unstubbed-decision`, `delegation-drift` and
`oversized-file` on the edits Items 4.1 and 4.2 make.
