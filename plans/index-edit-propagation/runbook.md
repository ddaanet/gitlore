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
| FR-B — a memory commit never records a carrier stale against the root index | FR15, FR8, FR11, NFR5 | 1 | 1.1 | outline §B; FR11 is what the dirty-only scope keeps intact |
| FR-F — a memory commit never adopts a tier gitlink moved off the pin the memory store records | FR15, FR8, FR11, NFR5, NFR2 | 1 | 1.2 | outline §B's "a refusal is reported, not fatal", narrowed: the pin half aborts |
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
  and that is where Phase 1's hook cases go.
  `tests/integration_gitlink_staging.bats` is where a real `git commit` drives
  the hook in all three index modes. Phase 1 adds no case there — nothing in
  this change stages into the parent index — but it is the regression boundary
  for the `GIT_INDEX_FILE` handoff the compose call now sits upstream of, so a
  red from it means the placement disturbed the staging order.
- **Where a conclusion lands.** The outline concludes the new decision in
  `docs/design.md`. The decision groups now live in `docs/decisions.md`, split
  from the hub along the need-time seam at `## Design Decisions` (changelog
  2026-09-07), and `scripts/check-docs-links.py` reads every conclusion line
  from that index. Item 4.2 targets it, and the hub's line cap is no longer in
  play.

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

  **After the freshness check, not before it.** The placement is not tidying:
  `gitlore_commit_msg_freshness` (`scripts/lib/util.sh:275`) compares the
  approved summary's mtime against the newest file under `$mempath`. Compose
  writes carrier files, so a compose placed ahead of that check makes the tree
  newer than the summary and every commit is refused as stale. Slice 1 catches
  the violation — the commit is refused and the carrier never lands — but the
  reason has to be recorded here or the constraint reads as arbitrary.

  Reporting is `gitlore_say_for_agent_or_user`, redirected to stderr, matching
  every other call to that helper in this file. Not
  `gitlore_compose_and_report`, which sets `GITLORE_COMPOSE_SYSMSG` /
  `GITLORE_COMPOSE_CTX` for a `PostToolBatch` hook to serialize and is
  meaningless to git.

  **The two message texts are fixed here, not invented at green time**, so a
  test can pin a phrase that exists before the test is written. Reuse
  `gitlore_compose_and_report`'s own wording:

  - rc 1 —
    `gitlore: tier composition refused — the memory indexes were left untouched:`
    then `gitlore_compose`'s problem lines (`scripts/lib/index-compose.sh:787`)
  - rc 2 —
    `gitlore: tier composition could not write an index — the memory indexes are only partly composed:`
    then the same (`:779`)

  `gitlore_say_for_agent_or_user` (`scripts/lib/log.sh:7`) takes an agent text
  and a user text and picks by `CLAUDECODE`, which bats neither sets nor clears:
  a test inherits whatever the invoking shell holds, and a subagent dispatch has
  `CLAUDECODE=1` in its ambient environment. Any case that reads one arm
  specifically has to set or unset it in the test body. Both arms carry the
  phrase above and differ only in the remedy sentence after it, so an assertion
  on the phrase holds whichever arm fires.

  **The rc-1 rule, as amended by Item 1.2.** As executed, this item treats every
  rc 1 alike — report, and let the commit proceed. That is right for a
  `gitlore_compose_check` refusal, which withholds a projection and destroys
  nothing, and wrong for a `gitlore_compose_check_pins` refusal: the commit's
  own `git -C "$mempath" add -A` adopts the moved gitlink, so the next compose
  projects root's older text over the carrier with nothing left to refuse on.
  The rule is therefore
  **a `gitlore_compose_check` refusal proceeds; a pin refusal aborts**, and Item
  1.2 implements the second half ahead of `gitlore_compose` and re-homes the two
  cases below that induce rc 1 off a pin mismatch. The slices below are as
  executed and are not rewritten here.

  Test-suite note: `tests/commit_memory.bats` currently loads `helpers/setup`,
  `helpers/fixtures`, `helpers/divergence-fixtures`;
  `tests/git_hook_pre_commit.bats` loads the same three. Both need
  `load helpers/tier-fixtures` for `make_tier_in_memory` / `set_tier_manifest` /
  `seed_tier_bullet` / `seed_root_bullet` / `commit_memory_state` /
  `assert_bullets`. `assert_bullets` calls `gitlore_index_part`, which lives in
  `scripts/lib/index-compose.sh`, and neither suite sources any lib today — so
  both also gain `source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"` in
  `setup()`. That file is function-only and safe to source twice, the property
  `scripts/lib/resolve.sh:5-13` already relies on. Both lines ride slice 1
  rather than a setup-only item.

  Slices:

  1. **External contract — the committed carrier is the composed one.** Fixture,
     shared by both tests: `make_parent_with_memory`,
     `make_tier_in_memory ddaanet`, `set_tier_manifest ddaanet`,
     `seed_tier_bullet ddaanet shared.md "stale hook"` — which also creates
     `memory/ddaanet/shared.md`, so the pointer is not dangling — then
     `seed_root_bullet "ddaanet/shared.md" "fresh hook"`, giving the root line
     `- [shared](ddaanet/shared.md) — fresh hook` against the carrier's
     `- [shared](shared.md) — stale hook`. Both writes stay uncommitted, so the
     store is dirty; an approved summary is written to
     `gitlore_commit_msg_file memory` — needed by the hook case, redundant but
     harmless for the `commit-memory.sh -m` case, which writes its own
     (`scripts/commit-memory.sh:61-63`).
     - `commit-memory composes the carrier into the commit it makes` in
       `tests/commit_memory.bats` — runs
       `scripts/commit-memory.sh -m <summary>`, writes
       `git -C memory/ddaanet show HEAD:MEMORY.md` to `$BATS_TEST_TMPDIR`, and
       asserts `assert_bullets` on that file equals exactly
       `- [shared](shared.md) — fresh hook`. Also asserts
       `git -C memory rev-parse HEAD:ddaanet` equals
       `git -C memory/ddaanet rev-parse HEAD`.
     - `the parent pre-commit hook composes the carrier before committing` in
       `tests/git_hook_pre_commit.bats` — runs `bash "$HOOK"`; asserts the same
       two conditions.

     Exact-block equality rather than a present-plus-absent pair: `stale hook`
     is a variant of `fresh hook`, so no single fault fails the negative on its
     own and the pair could only ever restate itself. The unprefixed carrier
     form is the one `tests/index_compose.bats:373` already pins for the down
     projection.

     The gitlink equality is already true today — the tier-first ordering at
     `scripts/lib/resolve.sh:900-905` exists to make it true — so it pins
     nothing alone. It is here because it costs one line and locks that ordering
     against a later reshuffle of the tier sync and the `add -A`; the block
     equality is what carries this slice.

     Both cases must fail against unchanged code on an assertion, not on a
     missing symbol: `gitlore_sync_memory_to_live` already exists and already
     commits, so the red is the committed carrier still reading `stale hook`.

  2. **Dirty-only scope — a clean store is not composed.** Composing a clean
     store creates a dirty state no approved summary covers, and the FR11 gate
     would then refuse a commit for a change the agent never made.

     **The fixture has to reach the guard.** `gitlore_sync_memory_to_live`
     returns at `scripts/lib/resolve.sh:885` when the store is clean *and*
     `HEAD` equals `live` — and that is exactly the state `make_tier_in_memory`
     leaves behind, since it fast-forwards every local branch onto the tier
     commit. A clean store built the obvious way therefore never enters the
     function's body at all, and the case would pass with the `dirty = 1` guard
     deleted, with the compose call absent, and with the whole feature reverted.
     Build it so it gets past that early return: seed the slice-1 divergence,
     `commit_memory_state`, then `git -C memory branch -f live HEAD~1` so `HEAD`
     sits one ahead of `live`, working tree clean, no `gitlore_commit_msg_file`
     present. The function then skips the dirty branch — the guard under test —
     and goes on to the `HEAD:live` fast-forward.
     - `a clean store is not composed by the commit path` in
       `tests/git_hook_pre_commit.bats` — runs `bash "$HOOK"`; asserts exit 0,
       that `gitlore_memory_dirty memory` still prints `0`, that
       `git -C memory rev-parse HEAD` is unchanged from before the run, and that
       `assert_bullets memory/ddaanet/MEMORY.md` still equals
       `- [shared](shared.md) — stale hook`. The dirty-state assertion is the
       discriminating one: composing here rewrites the carrier and the store
       goes dirty.
     - `the same store, made dirty, IS composed` — the positive that keeps the
       negative honest, over the same fixture differing only in the guard's
       trigger input. Add one uncommitted local fact — `memory/local.md` with
       frontmatter plus `seed_root_bullet "local.md" "a local fact"`, which
       leaves the tier side untouched — and a fresh approved summary; run the
       hook; assert the committed carrier now equals
       `- [shared](shared.md) — fresh hook`. Its own test body, never appended
       to the negative: a bats body runs under errexit, so a negative sitting
       behind a positive runs only in the case where the positive already held.

  3. **The compose return code decides — rc 1 reports and the commit proceeds,
     rc 2 aborts.** One `case` over `gitlore_compose`'s status, and both arms in
     one cycle because each is the other's control: an implementation that
     aborts on every non-zero rc passes the rc-2 case and fails the rc-1 one,
     and one that never aborts does the reverse. Written as separate cycles,
     each arm gets authored without the other's constraint in view. Both cases
     go in `tests/commit_memory.bats`; their inductions are independent and
     neither shares a fixture with the other.

     **rc 1 — an off-pin refusal is reported and the commit proceeds.**
     `gitlore_compose` returns 1 when `gitlore_compose_check` or
     `gitlore_compose_check_pins` refuses, having written nothing (D31, D36):
     projecting root's older text over an unadopted carrier would destroy
     approved upstream facts, so committing the carrier as-is is correct.
     Induction: an active, materialized tier whose worktree `HEAD` differs from
     the gitlink recorded in the memory store's **index** —
     `git -C memory rev-parse -q --verify ":ddaanet"` is what
     `gitlore_compose_check_pins` reads (`scripts/lib/index-compose.sh:323`),
     not `HEAD:ddaanet` — so reach it with a commit inside `memory/ddaanet` that
     is never `git -C memory add`-ed. The tier must not be mid-merge: slice 1's
     code review added a per-tier `gitlore_guard_stale_merge_state` immediately
     ahead of the compose, so a mid-merge tier returns 1 from
     `gitlore_sync_memory_to_live` and never reaches `gitlore_compose` at all —
     the case would then pin the guard rather than the rc-1 arm. Memory is
     otherwise dirty with a fresh approved summary, so the commit is reached.
     - `an off-pin compose refusal is reported and does not abort the commit`,
       run with `--separate-stderr` — asserts exit 0, that
       `git -C memory rev-parse HEAD` advanced past its pre-run value, and that
       `$stderr` carries both the header phrase `tier composition refused` and
       the fragment `is checked out at` from `gitlore_compose_check_pins`' own
       problem line. Exit-code-only would pass against unchanged code. Two
       strings rather than one because they fail for different faults: the
       header proves the rc-1 branch fired, the fragment proves the problem
       lines were forwarded rather than swallowed. Not the bare token `refused`
       — a token, not a phrase, on a channel other producers write to. A third
       string, the agent arm's remedy sentence
       `This commit also stages each tier at the commit its worktree is on now`:
       the case runs under `CLAUDECODE=1`, so that arm is the one chosen, and
       that sentence is the fix this slice's own code review made for its Major
       2 — the one telling an agent that the pin figure printed above is already
       stale. Nothing else pins it, so it would revert silently.

     **rc 2 — a write failure aborts the commit.** `gitlore_compose` returns 2
     when `gitlore_compose_write` fails partway, leaving the store partly
     composed; a half-written carrier must not be committed. Reuse the induction
     proven at `tests/index_compose.bats:921` — `chmod a-w memory/ddaanet`. What
     that fails is the **`mv`** at `scripts/lib/index-compose.sh:676`, not the
     temp write: `gitlore_compose_write` puts its temp file in the store's own
     gitdir via `rev-parse --absolute-git-dir` (`:656`), never beside the
     target. The two-line comment on the existing case (`:930-931`) says the
     opposite and is stale: rewrite it in this slice's commit to say the chmod
     fails the `mv` into the carrier's directory, and do not carry the wrong
     reading into the new case. Restore `chmod u+w` immediately after `run`, and
     guard with `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"`,
     the guard `tests/index_sync.bats:356` carries and the existing compose case
     lacks.
     - `a compose write failure aborts the commit` — asserts non-zero exit, that
       `git -C memory rev-parse HEAD` is unchanged, and that the approved
       `gitlore_commit_msg_file` still exists (the abort must not consume it, or
       the retry loses the user's approval). Then three strings on `$stderr`,
       for the same reason the rc-1 case gives — an exit code alone would pass
       against a silent abort, which is the worse failure: the header
       `tier composition could not write an index`, the forwarded problem line
       `could not write memory/ddaanet/MEMORY.md`, and the agent arm's remedy
       sentence
       `Investigate that path (permissions, disk space, a read-only worktree)`,
       which is the only thing that distinguishes this arm's instruction from
       the user arm's.

  4. **The abort keeps the approval, and the user arm reads right.** Slice 3
     landed rc 1 and rc 2; its code review then found that the rc-2 abort
     preserved the summary *file* but not its freshness, and fixed it in
     `62258fa` (`reports/item-1-1-s3-code-review.md`, Major 1) with no
     regression test — the fix was proven by a throwaway probe the reviewer
     deleted, the shape `CLAUDE.md` §Testing forbids. This slice puts that case,
     and the two surfaces the same report left unasserted, into the suite.

     **RED backs the fix out.** The `touch "$msgfile"` calls on the rc-2 and
     `*)` arms are committed, so the first two tests pass against the tree as it
     stands and there is no red to see. The RED dispatch deletes both `touch`
     lines in place, proves the two freshness tests fail on their assertions
     against the resulting SUT, and leaves it that way — tests uncommitted, fix
     backed out. GREEN restores both lines unchanged, and commits them with the
     tests. The backed-out state never reaches a commit; the slice commit is
     what finally carries the fix with a test.

     The third and fourth tests are characterization: the message texts they pin
     are already correct, so no red exists for them. Their discrimination is
     established at code review (d) by in-place mutation of the arm each one
     reads, on slice 2's precedent — the review report records which literal was
     mutated and that the test redded.

     **Second-granularity mtimes.** `gitlore_commit_msg_freshness`
     (`scripts/lib/util.sh:275`) compares whole seconds with `>=`, so a carrier
     written in the same second as the approved summary still reads `yes` and
     the defect does not appear. Every case below that turns on freshness sleeps
     1 second after writing the summary, before the run that is meant to stale
     it, and says why in a comment.

     - `an aborted compose keeps the approved summary usable` in
       `tests/git_hook_pre_commit.bats` — the case that would have caught Major 1. `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"` first.
       Two tiers, so that one carrier write lands before the failure and makes
       the tree newer than the msgfile: `make_tier_in_memory alpha`,
       `make_tier_in_memory beta`, `set_tier_manifest alpha beta`, a
       `seed_tier_bullet` / `seed_root_bullet` pair per tier leaving root
       disagreeing with *both* carriers, and an approved summary written to
       `gitlore_commit_msg_file memory`. `chmod a-w` the directory of whichever
       tier composes second — establish which that is from a run rather than
       assuming the manifest order, and record it in a comment; the case is void
       if the failing tier is the first composed, because then nothing was
       written and the msgfile was never staled. First `bash "$HOOK"`: assert
       non-zero, and that the msgfile still exists. Then `chmod u+w`, and a
       second `bash "$HOOK"` with **no new summary written**: assert exit 0 and
       that `git -C memory rev-parse HEAD` advanced past its pre-run value. The
       second run is the assertion that matters — file presence is what slice
       3's case already asserts, and it held throughout while the defect was
       live.

     - `an unrecognised compose status aborts and keeps the approval` in
       `tests/commit_memory.bats` — the `*)` arm, unreachable through
       `gitlore_compose`, which returns only 0, 1 or 2. Stub it: a driver script
       under `$BATS_TEST_TMPDIR` that sources `util.sh`, `log.sh` and
       `resolve.sh` (the order `gitlore_sync_memory_to_live`'s own header
       names), *then* defines `gitlore_compose`, then calls
       `gitlore_sync_memory_to_live memory`. The redefinition has to come after
       the sourcing — `scripts/lib/resolve.sh:11` pulls in `index-compose.sh`,
       which defines the real one. The stub prints a problem line, restamps a
       file under the store to stand for the partial write it is reporting
       (`touch memory/MEMORY.md` — without it nothing under `$mempath` is newer
       than the summary and the arm's restamp is unobservable), and returns 7.
       Fixture: memory dirty with a fresh approved summary; no tier needed.
       Assert non-zero exit, that `git -C memory rev-parse HEAD` is unchanged,
       that the stub's status `7` appears in the message, and that
       `gitlore_commit_msg_freshness memory` reads `yes` afterwards. That last
       one is this test's half of the red.

     - `the rc-1 user arm does not tell a user to retry a commit that succeeded`
       in `tests/commit_memory.bats` — slice 3's off-pin induction verbatim,
       with `CLAUDECODE` explicitly unset rather than `CLAUDECODE=1` — bats
       inherits the invoking shell's value, so the arm has to be chosen in the
       test body. Assert exit 0, that `$stderr` carries
       `ask it to repair the memory store.`, and that it does *not* carry
       `repair the memory store, then retry`. The two assertions are the same
       sentence's two endings, so no other producer on that channel can satisfy
       or break them by accident; the commit went through, so there is nothing
       to retry, and that contrast is the register fix the review made.

     - `the rc-2 user arm tells a user to retry` — the same treatment of slice
       3's `chmod a-w` induction, `CLAUDECODE` unset, carrying the same `id -u`
       skip and the same `chmod u+w` restore immediately after `run`. Assert
       non-zero exit and that `$stderr` carries
       `ask it to repair the memory store, then retry.`. Its own case rather
       than an addition to the one above: the inductions are different fixtures,
       and a bats body runs under errexit, so a second scenario appended to the
       first would only ever run when the first already held.

  **Residual — the `*)` arm's two remedy sentences stay unasserted.** Slice 4's
  stub case pins that arm's `unrecognised status (7)` text, and the rc-2 user
  case pins the `…, then retry.` ending the `*)` user arm happens to share
  verbatim, but neither `*)` remedy sentence is pinned in its own right, so
  either could be rewritten without a red. Left that way deliberately:
  `gitlore_compose` returns only 0, 1 or 2, so the arm is reachable only through
  a stub, and a second stub case bought solely to pin wording on an unreachable
  path costs more than the wording is worth.

- Item 1.2: `scripts/lib/resolve.sh` — a tier moved off its pin aborts the
  memory commit instead of being reported and committed through. Requirements:
  FR-F. Depends on: Item 1.1. Model: opus

  **Scheduled: after Phase 3, before Phase 4.** The slot was left open at plan
  time and settled at the Phase 2 checkpoint. It must land before Phase 4
  because Item 4.1's decision node describes the commit path's final behaviour
  and would otherwise argue a rule the code no longer follows; running it after
  Phase 3 rather than immediately keeps the relay work, which Item 2.1 just made
  load-bearing, in one uninterrupted run.

  **The defect.** Measured through the `pre-commit` entry point against the code
  Item 1.1 landed, with a tier whose carrier held an approved upstream fact and
  a root index line carrying older text. Run 1 refuses with rc 1
  (`tier composition refused … is checked out at …`), reports, and lets the
  commit proceed — and the commit's own `git -C "$mempath" add -A` then stages
  the tier's moved gitlink, which removes the very condition
  `gitlore_compose_check_pins` refused on. Run 2 — any later memory commit, a
  SessionStart, or a `PostToolBatch` compose — projects root's older text over
  the carrier with no refusal at all; `gitlore_sync_tiers_to_live` commits that
  inside the tier and advances the tier's local `live`, which `pre-push`
  publishes to the tier's own remote. The approved upstream fact is destroyed,
  and then shipped, one commit after the warning.

  Not a regression: `add -A` predates this job, and before the commit path
  composed at all the same sequence ended in the same overwrite at the next
  SessionStart. What Item 1.1 adds is one more trigger for run 2, and a warning
  at run 1 that did not exist before.

  **The change.** Call `gitlore_compose_check_pins "$mempath"` at the
  `gitlore_sync_memory_to_live` call site, after the up-front per-tier
  stale-merge guard loop and immediately **before**
  `compose_result=$(gitlore_compose "$mempath")`, capturing its problem lines;
  on its non-zero return, report and `return 1`. About six lines.

  **At the call site, not inside `gitlore_compose`.** That function collapses
  `gitlore_compose_check` and `gitlore_compose_check_pins` into one rc 1, so the
  call site cannot tell a stale pin from a broken index line, and splitting the
  rc would change a contract its three other callers (`session-start.sh`, the
  `PostToolBatch` hook, `add-tier-batch.sh`) and slice 4's stub case all depend
  on. Calling the pin check directly leaves the 0/1/2 contract untouched — the
  `*)` arm's comment and slice 4's stub stay true — and costs one `rev-parse`
  per active tier, all reads.

  **No restamp.** `gitlore_compose_check_pins` writes nothing, so when this
  aborts the tree is no newer than the approved summary and
  `gitlore_commit_msg_freshness` still reads `yes`. The `touch "$msgfile"` the
  rc-2 and `*)` arms carry is not wanted here: those arms restamp because
  something was written, and copying it would be a lie about what ran.

  **The cost to the user is real and accepted.** An off-pin tier blocks every
  **parent** commit until the tier is returned to its pin or `/gitlore:merge` is
  run. That is the shape `gitlore_guard_stale_merge_state` already commits to
  for a comparable condition, and the refusal is self-describing — it carries
  the verbatim `git -C "<abs>" checkout --detach <pinned>` command from
  `gitlore_compose_check_pins`' own problem line (NFR2). The trade is silent
  destruction of approved upstream facts against a blocking, self-describing
  refusal, and every other D31/D36 decision in this codebase takes the refusal.

  **The two message texts are fixed here, not invented at green time**, so a
  test can pin a phrase that exists before the test is written. Reporting is
  `gitlore_say_for_agent_or_user` redirected to stderr, matching every other
  call in this file, with the header held in one `local` variable interpolated
  into both arguments so the arms cannot drift apart — the shape Item 1.1's rc-1
  and rc-2 arms already use. Both arms carry the header and the forwarded
  problem lines and differ only in the remedy sentence after them:

  - header —
    `gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:`
    then `gitlore_compose_check_pins`' problem lines
  - agent remedy —
    `gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Return the tier to its pin with the command above, or run /gitlore:merge to take its content properly, then retry the commit — the approved summary is still in place.`
  - user remedy —
    `gitlore: composing would have overwritten what that tier holds. Open this project in Claude Code and ask it to repair the memory store, then retry.`

  **Two of Item 1.1's cases induce rc 1 off a pin mismatch**, so both assert the
  behaviour this item removes and both are re-homed in the slices below:
  `an off-pin compose refusal is reported and does not abort the commit` and
  `the rc-1 user arm does not tell a user to retry a commit that succeeded`,
  both in `tests/commit_memory.bats`. The surviving rc-1 arm is a
  `gitlore_compose_check` refusal, whose cheapest induction is a manifest
  listing an unmounted tier — `set_tier_manifest ddaanet phantom` with no
  `make_tier_in_memory phantom` — giving the problem line
  `the tier manifest lists 'phantom', which is not mounted in …` (rule 2,
  `scripts/lib/index-compose.sh:177-180`) and reaching `gitlore_compose` because
  the pin check passes.

  **Expect fallout outside these two suites** wherever a test commits memory
  with a tier deliberately ahead of what memory's index records —
  `tests/tier_divergence.bats` and `tests/tier_lockstep.bats` first. A path that
  legitimately advances a tier stages the moved gitlink as its last act (D43),
  so the pin check should pass; verify that from a run rather than assuming it.

  Slices:

  1. **External contract — an off-pin tier aborts the commit and the gitlink is
     not adopted.** Fixture: Item 1.1 slice 3's off-pin induction verbatim —
     `make_parent_with_memory`, `make_tier_in_memory ddaanet`,
     `set_tier_manifest ddaanet`,
     `seed_tier_bullet ddaanet shared.md "stale hook"`,
     `seed_root_bullet "ddaanet/shared.md" "fresh hook"`, then
     `git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"`,
     never staged into memory's index. Memory is otherwise dirty with a fresh
     approved summary, so the commit is reached.
     - `a tier moved off its pin aborts the commit` in
       `tests/commit_memory.bats`, replacing
       `an off-pin compose refusal is reported and does not abort the commit` —
       runs `CLAUDECODE=1 run --separate-stderr bash "$CMD" -m <summary>`;
       asserts non-zero exit, that `git -C memory rev-parse HEAD` is unchanged
       from its pre-run value, that `git -C memory rev-parse ":ddaanet"` is
       unchanged, that `assert_bullets memory/ddaanet/MEMORY.md` still equals
       `- [shared](shared.md) — stale hook`, that
       `gitlore_commit_msg_file memory` still exists and
       `gitlore_commit_msg_freshness memory` reads `yes`, and that `$stderr`
       carries the header fragment
       `moved off the commit the memory store records for it`, the forwarded
       fragment `is checked out at`, and the agent remedy fragment
       `Return the tier to its pin with the command above`. The unchanged
       `:ddaanet` and the unchanged carrier are the assertions this item exists
       for — the exit code alone would pass against an abort that had already
       staged the move.
     - `the parent pre-commit hook aborts on an off-pin tier` in
       `tests/git_hook_pre_commit.bats` — the same fixture through
       `bash "$HOOK"`; asserts non-zero exit, the unchanged `:ddaanet` gitlink
       and the unchanged carrier. The second entry point, for the reason Item
       1.1 slice 1 gives: one shared body, two callers, and what is at stake is
       what reaches the tier's remote.

     Both must fail against unchanged code on an assertion, not on a missing
     symbol: `gitlore_compose_check_pins` already exists and already refuses, so
     the red is the commit having landed with `:ddaanet` moved.

     **As executed, this slice also carried two things the list above does not
     name.** First, slice 3's re-induction of
     `the rc-1 user arm does not tell a user to retry a commit that succeeded`,
     pulled forward: its fixture is the off-pin induction, so landing the abort
     reds it, and leaving it to slice 3 would mean two commits with the suite
     red. Assertions unchanged, induction swapped to slice 2's manifest refusal,
     exactly as slice 3 specified it. Second, the trailing clause of the rc-1
     agent remedy — `, so a pin figure printed above is the one from before it`
     — was dropped, and the arm's comment rewritten to say why. Verified at code
     review: `gitlore_compose` runs both checks and returns 1 on either, and the
     pin guard aborts ahead of it, so rc 1 reaches that arm only from
     `gitlore_compose_check`, whose four problem-line producers emit no commit
     id. The clause described a state the code cannot produce, and slice 2 was
     about to pin it.

  2. **A `gitlore_compose_check` refusal still proceeds.** The other half of the
     amended rule, and slice 1's control: an implementation that aborts on every
     refusal passes slice 1 and fails this, and one that aborts on neither does
     the reverse. Its own case rather than an addition to slice 1's — the
     fixtures differ, and a bats body runs under errexit.
     - `a manifest refusal is reported and does not abort the commit` in
       `tests/commit_memory.bats` — the same fixture with the tier left **on**
       its pin and `set_tier_manifest ddaanet phantom`; runs with `CLAUDECODE=1`
       and `--separate-stderr`; asserts exit 0, that
       `git -C memory rev-parse HEAD` advanced past its pre-run value, and that
       `$stderr` carries `tier composition refused`, the fragment
       `the tier manifest lists 'phantom'`, and the rc-1 agent remedy sentence
       `This commit also stages each tier at the commit its worktree is on now`.
       That fragment is the whole sentence after slice 1 dropped its trailing
       clause, not the first half of a longer one.
     - `a mid-merge tier is reported as a merge, not as a moved pin` in
       `tests/commit_memory.bats` — added from slice 1's code review, which
       measured that hoisting the pin guard above the per-tier
       `gitlore_guard_stale_merge_state` loop leaves both suites green, so
       nothing pins that ordering. The two guards answer the same tier with
       different remedies, and `gitlore_compose_check_pins`' own mid-merge line
       is the weaker one: it offers `checkout --detach`, which unlinks
       `MERGE_HEAD` and destroys the prepared merge. Fixture: slice 1's off-pin
       induction plus a `MERGE_HEAD` written into the tier's gitdir, the shape
       the neighbouring stale-merge case already uses. Asserts non-zero exit and
       that `$stderr` carries the merge directive rather than
       `moved off the commit the memory store records for it` — the tier being
       both mid-merge **and** off its pin is what makes the two guards
       distinguishable, which is why the existing mid-merge case, whose tier
       sits on its pin, discriminates nothing here.

  3. **The user arms read right.** The pin abort gets its own user-arm case,
     where a retry *is* the right instruction. Item 1.1 slice 4's
     `the rc-1 user arm does not tell a user to retry a commit that succeeded`
     was to be re-induced onto slice 2's manifest refusal here; slice 1 carried
     that instead, for the reason recorded there, so this slice is one case.
     - `the pin-abort user arm tells a user to retry` — slice 1's fixture,
       `CLAUDECODE` unset; asserts non-zero exit, that `$stderr` carries the
       header fragment `moved off the commit the memory store records for it`
       and `ask it to repair the memory store, then retry.`, and that it does
       *not* carry `Return the tier to its pin`, which is the agent arm's. The
       header fragment is what discriminates: that `…, then retry.` ending is
       shared verbatim with the rc-2 and `*)` user arms, so on its own it pins
       nothing.

  **Residual — an interrupted `/gitlore:merge` continuation aborts under a
  remedy that would undo the repair.** Found at slice 1's code review, left
  unfixed. `gitlore_guard_stale_merge_state` does not always refuse: on
  `stale-no-merge-head` it delegates to `gitlore_recover_stale_no_merge_head`,
  which can repair and return 0 — and neither of its branches stages the moved
  gitlink in memory's index, which is what the normal continuation does as its
  last act (D43). So the loop can hand the pin guard a tier that is off its pin
  *because gitlore just repaired it*: the commit aborts, and the remedy says the
  tier "was moved outside /gitlore:merge" and offers
  `checkout --detach <pinned>`, which would move HEAD off a landed, approved
  merge. Bounded — reachable only from a continuation interrupted between its
  merge commit and its staging; nothing is destroyed, the merge commit stays
  reachable, the same sentence offers the correct alternative
  (`or run /gitlore:merge to take its content properly`), and
  `gitlore_recover_landed_merge`'s own message prints immediately before the
  abort. The fix is a design call outside this item — either the recovery path
  stages the gitlink it moved, or the accepted blocking cost covers this case
  too.

  **Residual — the pin guard covers active tiers, `add -A` covers mounted
  ones.** `gitlore_compose_check_pins` iterates `gitlore_active_tiers`, while
  `gitlore_sync_tiers_to_live` and the `add -A` that follows it reach every
  mounted tier. A mounted-but-unlisted tier moved off its pin is therefore still
  adopted silently. Narrower than the case this item fixes — root holds no line
  for a dormant tier, so no down projection overwrites it, which is what made
  the active-tier scope the right one for composition — but the adoption itself
  is unguarded.

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
  thread of an `--agent` session (`memory/ddaanet/hook-input-schema.md`, which
  also fixes it as a top-level stdin field). The string `agent_id` appears
  nowhere under `scripts/` today, so each of the four consumers gains a new
  `jq -r '.agent_id // empty'` read — and two of the four do not hold the
  payload at all yet:

  - `scripts/cc-hooks/index-sync-pre.sh:40-41` — already holds `$payload`.
  - `scripts/cc-hooks/index-sync-post.sh:30` — already holds `$payload`.
  - `scripts/cc-hooks/index-compose.sh:32` — currently `cat >/dev/null` at line
    23 to drain the payload; it must capture it instead and read `agent_id` from
    it. The comment at lines 18-23 saying the stamp and not the payload's
    contents is the signal stays true of the *trigger*; it needs the qualifier
    that the payload is now also read for the agent id.
  - `scripts/cc-hooks/add-tier-batch.sh:75` — drops the compose hook's baseline;
    that drop must target the same keyed path. Same shape as index-compose.sh
    and not a payload already in hand: it drains with `cat >/dev/null || true`
    at line 38 and must capture instead, under `set -euo pipefail`, so
    `payload=$(cat || true)`. Its header comment at line 20 — "The intent file
    IS the signal, so the batch payload is unused" — becomes false with that
    read and takes the same qualifier as index-compose.sh's.

  `scripts/cc-hooks/index-sync-pre.sh:43-47` carries the comment this change
  falsifies — "Each post hook removes its own file at batch end (even when
  nothing was touched), so an existing one here always belongs to the batch in
  flight." That is the invalidated assumption itself: rewrite it to say the
  baselines are keyed per agent, so an existing one belongs to the batch in
  flight *of this agent*.

  Bound the stranded-file residual in a comment rather than adding a sweeper,
  the way `index-sync-post.sh:35-38` already bounds a stale pre-image: a
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
       without the field; asserts both unsuffixed paths exist and no keyed file
       does.
     - `an agent id outside [A-Za-z0-9-] cannot leave the gitdir` — added at the
       slice 1 boundary, not in the plan as proofed. Slice 1's code review found
       the id spliced raw into `rev-parse --git-path`, which normalises nothing,
       so a `/` or `..` component walks the returned path out of the gitdir to
       somewhere the consumers `cp` onto and `rm -f`; the fix is
       `_gitlore_agent_suffix` (`scripts/lib/index-sync.sh`), collapsing
       everything outside that class to `_` via `LC_ALL=C tr -c`. It landed with
       the code-review fixes and **no test pins it**, which is how the four
       remedy sentences of D-2 came to mutate green. Assert that
       `gitlore_index_preimage_file memory ../../../etc/passwd` stays under
       `git -C memory rev-parse --git-path .` — equality against the sanitized
       name, not a `*` glob, for the reason the slice 1 test review gives — and
       the same for `gitlore_compose_stamp_file`. Also assert `agent-7` passes
       through byte for byte, so the guard cannot silently widen.

     **Red for that case is obtained by mutation, not by absence.** The guard is
     already committed, so a test written against the tree as it stands passes.
     The RED dispatch backs `_gitlore_agent_suffix`'s body out to a plain
     `printf -- '-%s' "$1"` passthrough to red against, and GREEN restores it —
     the same shape Item 1.1 slice 4 used, and a decision for the TDD audit to
     read as one rather than as a process defect.

     `tests/index_sync.bats` drives the hooks through `pre_stdin` (`:109`),
     `post_stdin` (`:136`) and `batch_payload` (`:140`); `batch_payload` gains
     an optional agent id in this slice, the same way the helpers do. Assert the
     absence of a keyed file with `find`, not with a glob or an `ls` pipeline —
     bash 3.2 leaves an unmatched glob as a literal, and the gitdir path may
     contain whitespace: `[ -z "$(find "$(dirname "$(gitlore_index_preimage_file
     memory)")" \
     -maxdepth 1 -name 'gitlore-index-preimage-*')" ]`.

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
       emitted nothing. The suite's `pre()` takes only a file name today and its
       `feed()` (`tests/cc_hook_index_compose.bats:27,36`) takes no argument at
       all, piping a literal `{}` — both gain an optional agent id, which is
       work in this slice, not an affordance already there.
     - `add-tier-batch drops the compose baseline for its own agent` in
       `tests/cc_hook_add_tier.bats` — that suite owns `add-tier-batch.sh`
       (`:11`), not the compose one. Asserts that with `agent_id: "a1"` on the
       batch payload, `add-tier-batch.sh` removes
       `gitlore_compose_stamp_file memory a1` and leaves an
       independently-created bare stamp in place.

---

## Phase 3: Relay a subagent's reports to the parent (type: tdd)

- Item 3.1: `scripts/lib/index-sync.sh` and three hooks — a hook firing inside a
  subagent writes its report to a keyed marker; the next parent-side run folds
  the markers into its own report and removes them. Requirements: FR-D. Depends
  on: Item 2.1. Model: opus

  Settled empirically, not assumed: a hook firing inside a subagent has both its
  `systemMessage` and its `hookSpecificOutput.additionalContext` confined to
  that subagent — the parent transcript carries zero `hook_*` attachments while
  the subagent's own JSONL carries all four, and the no-subagent control
  surfaces both channels normally (`subagent-hook-output-probe.md`, CC 2.1.261).
  So a subagent's edit to the root index composes, and the report reaches
  neither the parent's context nor the user.

  The marker is a new untracked `rev-parse --git-path gitlore-…` file in the
  memory gitdir, beside `gitlore-nudged` (`scripts/lib/util.sh:163`),
  `gitlore-merge-state` (`:217`), the `gitlore-merge-<artifact>` briefing files
  (`gitlore_merge_artifact_file`, `:226`), `gitlore-index-preimage` and
  `gitlore-compose-stamp` — five existing names, so the relay marker is the
  sixth. One helper serves both reports: the confinement is a property of the
  event, not of the script.

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

  **Two channels, not one.** `systemMessage` is the user's and
  `additionalContext` is the model's (`memory/ddaanet/hook-output-channels.md`
  §2), so a drain that returns one blob on stdout cannot feed both, and calling
  it twice is not an option — the first call removes the markers. The relay
  takes the shape the codebase already uses for exactly this:
  `gitlore_compose_and_report` sets `GITLORE_COMPOSE_SYSMSG` /
  `GITLORE_COMPOSE_CTX` (`scripts/lib/index-compose.sh:794,796`) and its two
  consumers serialize them (`index-compose.sh:55-56`,
  `add-tier-batch.sh:80-85`).

  Interfaces:
  - `gitlore_relay_marker_file <mempath> [<agent_id>]` → prints the absolute
    path of the relay marker; unsuffixed when the agent id is empty or absent
  - `gitlore_relay_write <mempath> <agent_id> <sysmsg> <ctx>` → returns 0 after
    writing both report bodies to the keyed marker; returns non-zero without
    writing when the marker cannot be created. File format: the literal line
    `--- gitlore-relay-sysmsg ---`, the systemMessage body, the literal line
    `--- gitlore-relay-ctx ---`, the additionalContext body. Either body may be
    empty; neither may contain a line equal to a delimiter, which nothing
    reaching this helper does.
  - `gitlore_relay_drain <mempath>` → returns 0 always; removes every keyed
    marker in the memory gitdir and sets `GITLORE_RELAY_SYSMSG` and
    `GITLORE_RELAY_CTX` to the accumulated blocks, each block carrying one
    framing line naming the agent id its filename suffix holds. Both are set to
    the empty string when no marker exists. Enumerate the markers
    whitespace-safely — a quoted-prefix glob over the gitdir path or
    `find -print0`, never an `ls` pipeline, since the gitdir path may contain
    spaces — and fold the blocks in filename order, so a two-marker assertion
    cannot flake on directory order.

    Only half of that clause is reachable by test, established at slice 1 by
    mutation: an unquoted glob reds against the spaced-gitdir case, an `ls`
    pipeline ships green. `ls` prints basenames, and a marker basename is
    `gitlore-relay-` plus what `_gitlore_agent_suffix` emits — `[A-Za-z0-9-]`,
    no whitespace by construction — so the space lives in the prefix `ls` never
    prints. The `ls` half stays as a style rule with no reachable failure. Do
    not add a test for it; a test that cannot fail is worse than the gap.

  **Red shape.** All three helpers are new, and `tests/index_sync.bats` sources
  `scripts/lib/index-sync.sh` directly in `setup()` (`:12`), so a slice-1 case
  written against the finished names would red with `command not found` —
  absence, not wrongness. Land the three as inert stubs first:
  `gitlore_relay_marker_file` printing the unsuffixed path whatever its second
  argument, `gitlore_relay_write` returning 0 and writing nothing,
  `gitlore_relay_drain` returning 0 with both variables empty. Every slice-1
  assertion then fails on its own assertion, and any that comes back green
  against the stub has identified itself as vacuous. Phases 1 and 2 need no such
  step — their SUTs exist and their helpers already take the arguments, ignoring
  the new one.

  Slices:

  1. **External contract — write keyed, drain unkeyed.**
     - `relay_marker_file suffixes the agent id` in `tests/index_sync.bats` —
       asserts `gitlore_relay_marker_file memory a1` equals the gitdir's
       `gitlore-relay-a1`, and that both `gitlore_relay_marker_file memory` and
       `gitlore_relay_marker_file memory ""` equal the unsuffixed name. Equality
       against an independently computed `rev-parse --git-path`, not a trailing
       glob and not a baseline taken from the SUT: a glob accepts any path
       ending in `-a1`, and the empty-string id is the input
       `_gitlore_agent_suffix` is most likely to get wrong. The two unsuffixed
       halves run first so the keyed failure does not hide them.
     - `relay_write then relay_drain splits the two channels and removes the marker`
       — writes a sysmsg `S1` and ctx `C1` under `a1`, drains, asserts
       `$GITLORE_RELAY_SYSMSG` contains `S1` and the framing line naming `a1`,
       `$GITLORE_RELAY_CTX` contains `C1` **and** its own framing line naming
       `a1`, **neither** carries the other's body, and
       `gitlore_relay_marker_file memory a1` no longer exists. The cross-check
       is what pins the split: a drain that concatenated both bodies into both
       variables would pass a one-sided assertion. Both channels carry framing,
       or a drain that framed only the user-facing one passes.
     - `relay_drain folds two markers in filename order, over a gitdir path holding a space`
       — builds the parent out of line under a spaced root, guards that the
       marker path really contains a space, writes markers under `a1` and `a2`,
       and pins order with a single `*"S-one"*"S-two"*` match rather than two
       presence checks. Without it an `ls` pipeline, an unquoted glob and a
       reverse fold all pass the whole item: no other case in slices 1-4 has a
       spaced path or a second marker.
     - `relay_drain on an empty store sets both variables empty and returns 0` —
       pre-seeds both variables with sentinels and plants a
       `gitlore-compose-stamp` decoy in the gitdir, then asserts status 0, that
       both variables are the empty string, and that the decoy survives. Without
       the sentinels the case is satisfied by birth state, since bats starts
       each test with the variables unset; the decoy is what catches a
       `gitlore-*` enumeration eating Item 2.1's compose baseline. This case
       cannot red against the inert stub — the stub is specified to do the
       correct thing on the degenerate input — and that is recorded rather than
       engineered away.

     Every call to `gitlore_relay_write` / `gitlore_relay_drain` in these cases
     captures the return status explicitly (`run …` for the write,
     `rc=0; … || rc=$?` for the drain, which must keep its two variables). A
     bare call in a bats body runs under errexit and aborts the test instead of
     failing a named assertion, so both contracts' "returns 0" halves would be
     pinned by nothing.

  2. **Both PostToolBatch reports relay on the same wiring — write when keyed,
     fold in when not.** `index-compose.sh` and `index-sync-post.sh` converge on
     the same shape before they emit: a sysmsg/ctx pair, a non-empty guard over
     it, and one `jq -n` (`index-compose.sh:55-59`,
     `index-sync-post.sh:232-240`). The relay is the same insertion at the same
     point in both, which is why the two hooks are one cycle rather than two —
     authored separately, one mechanism acquires two shapes, and the constraint
     that binds both is easy to see only once: the fold must precede the
     emission guard, or a parent-side run whose only report is a relayed one
     emits nothing. Both hooks also exit early, upstream of the report path,
     when nothing they watch changed, so a marker is not necessarily drained by
     the very next parent-side batch; slice 3 is the backstop for that.

     Four cases, two per hook, each hook keeping its own keyed/unkeyed pair —
     the keyed case pins that the subagent still gets its own report, the
     unkeyed one that the parent gets the relayed block and the marker is gone.
     - `a keyed compose run writes a marker and still emits its own json` in
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
     - `a keyed index-sync run writes its replacement report to a marker` in
       `tests/index_sync.bats` — pre- and post-hook with `agent_id: "a1"` over
       an index line whose hook changed; asserts the keyed marker contains the
       `reset frontmatter to match MEMORY.md` line and the `• <path>:` bullet.
     - `an unkeyed index-sync run folds in the marker` — asserts the unkeyed
       post-hook's `systemMessage` carries the relayed block attributed to `a1`
       and the marker is removed.

  2.5. **One agent, one marker, several reports — the write merges instead of
  truncating.** Added after slice 2's code review. `hooks/hooks.json` registers
  `index-sync-post.sh` and `index-compose.sh` on the *same* `PostToolBatch`
  event, and both now stage to `gitlore_relay_marker_file <mempath> <agent_id>`
  — one path per agent. The write is a single `>` redirect, so in a subagent
  batch that edits `MEMORY.md` with a tier mounted — the ordinary case — the
  compose hook truncates the sync hook's staged report and the parent receives
  only one of them. The frontmatter-sync report, the one telling the actor its
  authored `description:` was overwritten, is the one lost. The same mechanism
  loses a report across batches: a subagent editing the index in two successive
  batches has the first marker truncated by the second, because nothing
  parent-side runs in between — the parent is blocked inside the `Task` call for
  the subagent's whole lifetime. Demonstrated by hand-run in
  `reports/item-3-1-s2-code-review.md` §F1.

     This falsifies FR-D for the common case, so it is fixed here rather than
     deferred: "reports produced inside a subagent reach the parent session"
     does not hold if one hook's report evicts another's.

     **`gitlore_relay_write` merges into an existing marker for the same agent**
     rather than truncating: when the marker exists, parse its two channels,
     append the new bodies to their own channels, and write the result back. One
     marker per agent still, one framing line per agent at the parent, with both
     hooks' text under it.

     Chosen over the two alternatives the code review named, both of which cost
     more. Keying the marker per source (`<agent_id>-compose`) makes the drain
     parse a compound suffix to recover the agent id for its framing line, and
     the suffix is not unambiguously splittable — `_gitlore_agent_suffix` emits
     `[A-Za-z0-9-]`, so both `-` and, via the `tr -c` fold, `_` can occur inside
     an agent id. Plain append-without-parse would put a second
     `--- gitlore-relay-sysmsg ---` pair mid-file, which the drain's `awk` reads
     as the ctx delimiter arriving twice, mis-splitting the result. Merging per
     channel changes neither the file format nor the marker's name, so every
     committed slice-1 contract case still describes the helper: a single write
     to a fresh marker is byte-identical to today's.

     - `relay_write merges a second report into an existing marker` in
       `tests/index_sync.bats` — writes `S1`/`C1` under `a1`, writes `S2`/`C2`
       under `a1` again, drains once. Four assertions: the marker's bytes after
       the **first** write, a count of `gitlore-relay-*` files taken before the
       drain, and the two drained channels as **exact blocks**.

       Not the shape this entry first specified. A framing-line count was named
       here as the thing distinguishing a merge from a second marker, and
       measurement showed it distinguishes nothing: an implementation writing a
       second marker keys it `gitlore-relay-a1-2`, which the drain frames
       `--- gitlore-relay agent a1-2 ---`, so the counted literal
       `--- gitlore-relay agent a1 ---` still occurs exactly once. Every
       assertion in the draft was phrased in terms of the `a1` name and the
       wrong implementation leaves that name intact, so it passed both suites
       entire. A file count sees it; nothing phrased in terms of the text does.

       The byte assertion on the first write pins the premise this whole design
       choice rests on — that a single write to a fresh marker is unchanged, so
       the committed slice-1 contract cases still describe the helper. Nothing
       pinned it before: a merge drifting the fresh write by one leading newline
       per body passed every committed case.

       Exact blocks rather than ordering substrings plus cross-checks: under
       bats' errexit each assertion in such a chain runs only when its
       predecessor held, so the group is pinned by whichever fails first and
       nothing exercises the rest. One equality per channel subsumes all six and
       cannot go vacuous.
     - `both PostToolBatch hooks in one keyed batch reach the parent` in
       `tests/cc_hook_index_compose.bats` — a real keyed run of
       `index-sync-post.sh` followed by a real keyed run of `index-compose.sh`
       over one batch that moves the index in a store with a tier mounted, then
       an unkeyed compose run; asserts the parent's `systemMessage` carries
       **both** the `reset frontmatter to match MEMORY.md` line and the
       `recomposed tier pointers` line. This is the case that reds against the
       defect as found; the helper-level case above is what pins the mechanism.

     Slice 4's
     `relay_write refuses an empty agent id and a squatted marker path` still
     applies unchanged — a merge still has one create path and one failure mode.

  3. **SessionStart drains a marker that outlived its session.**
     - `session-start drains a stranded relay marker` in
       `tests/cc_hook_session_start.bats` — that suite owns `session-start.sh`,
       not the compose hook's. Writes a marker under `a1` with
       `gitlore_relay_write`, runs `scripts/cc-hooks/session-start.sh`; asserts
       its `systemMessage` carries the relayed body text *and* the framing line
       naming `a1`, and that `gitlore_relay_marker_file memory a1` is gone.
     - `session-start with no marker emits no relay framing` — the negative that
       keeps the positive honest, over the same fixture differing only in
       whether a marker exists: asserts the SessionStart `systemMessage` carries
       no framing line. Hold the framing literal in one variable at the top of
       the test file, asserted by both cases and defined test-side rather than
       sourced from the lib — sourcing it moves both sides together and the
       positive stops pinning the wording.

  4. **A marker that cannot be written does not lose the report.**
     - `a failed relay write leaves the subagent's own report intact` in
       `tests/cc_hook_index_compose.bats` — induce with
       `mkdir "$(gitlore_relay_marker_file memory a1)"`, so the write fails with
       "Is a directory"; no permission bits, so no root guard and nothing to
       restore. Asserts the hook still exits 0 and its own `systemMessage` still
       carries the compose report. A hook that aborted here would trade a relay
       failure for a total one. Not `chmod a-w` on the gitdir:
       `gitlore_compose_write` puts its temp file in the gitdir
       (`scripts/lib/index-compose.sh:656`, the fact Item 1.1 slice 3 rests on),
       so a read-only gitdir fails compose itself with rc 2 before the relay is
       reached, and the case would assert the wrong failure.
     - `relay_write refuses an empty agent id and a squatted marker path` in
       `tests/index_sync.bats` — asserts `gitlore_relay_write` returns non-zero
       and leaves the gitdir entry-free under both inputs. Added after slice 1:
       the write's whole failure contract ("returns non-zero", "without
       writing") was pinned by nothing, and the hook-level case above does not
       reach it — a write wrongly returning 0 satisfies that case too. The
       empty-id half is a contract addition, `[ -n "$agent_id" ] || return 1`,
       landing in this slice's GREEN: the drain enumerates keyed markers only,
       so an unkeyed write strands a file nothing folds and nothing removes.
       Deferred to here rather than slice 1 because this is the slice that owns
       the write's failure paths.
     - `relay_write joins a channel only when the old body is non-empty` in
       `tests/index_sync.bats` — `gitlore_relay_write mem a1 "S" ""` then
       `gitlore_relay_write mem a1 "S2" "C2"`, asserting the drained ctx block
       carries no leading blank line. The slice 2.5 review fixed this and could
       not pin it: no frozen case writes an empty ctx. Reachable in production —
       `index-sync-post.sh`'s `failed` block sets a sysmsg with no ctx, so a
       subagent batch whose frontmatter sync fails and whose compose then
       reports takes exactly this path.
     - `an unreadable marker costs the relay, not the hook` in
       `tests/index_sync.bats` — a marker at mode 0200, then a drain; asserts
       the drain returns 0 and the calling hook still emits its own report. Pair
       it with a SessionStart case in `tests/cc_hook_session_start.bats`
       asserting the hook exits 0 and its `additionalContext` still carries the
       commit-protocol text over the same fixture. Slice 3's review measured
       what an unguarded drain costs there and it is not merely the relay: the
       `awk` rc 2 propagates under `set -euo pipefail`, the hook exits 2 with
       empty stdout, and every notice accumulated above the fold goes with it —
       the launcher warning, the divergence and tier notices, and the standing
       FR11 commit-protocol context. Slice 3 fixed the caller with
       `gitlore_relay_drain "$mempath" || true` and could not pin it: no frozen
       case creates an unreadable marker, and removing the `|| true` leaves both
       slice-3 cases green. After that fix the body is still lost and only the
       framing line reaches the user, which is what the `index-sync.sh` side
       closes. `find -type f` screens non-files, not permissions, so `awk` exits
       2 and under the hooks' `set -euo pipefail` takes the whole hook down —
       the same shape as the write's, which slice 2.5 fixed on its own side with
       `|| old_sys=""`. Fixing the drain changes what it does with a marker it
       cannot read (fold an empty block and `rm -f` it), which is why it wants a
       case rather than a one-line ride-along on a refactor.
     - `an unkeyed run survives a non-file squatting on a marker name` in
       `tests/cc_hook_index_compose.bats` — after the `mkdir` above, fire the
       compose hook *unkeyed* over an index edit; asserts it still exits 0 and
       still emits its own report. This is the drain's half of the same fixture,
       and the regression it pins is real: `awk` and `rm` both fail on a
       directory, and under the hooks' `set -euo pipefail` that aborts the hook
       before it writes any JSON, so a failed relay costs the entire report.
       `gitlore_relay_drain`'s `-type f` is what prevents it, and slice 1 has no
       case that makes a directory marker.

  5. **A relay that fails says so, on the channel a subagent can actually be
     heard on.** Added after slice 4's code review. Slice 4 stopped a failed
     relay write from taking its hook down, and in doing so traded a loud total
     failure for a silent partial one: the parent loses a report, and nobody —
     not the parent, not the user, not the acting subagent — learns it existed.
     That defeats FR-D on precisely the run FR-D is for, and the project's rule
     is that a silent-to-everyone path must be fixed. The rule's escape clause
     does not apply: the condition is an exit status the caller already holds,
     so the signal is observed rather than inferred and cannot false-alarm.

     Reachable, and the report lost is a consequential one.
     `gitlore_compose_and_report` catches a compose write failure, sets its
     report to "the memory indexes are only partly composed", and returns 0 — so
     on an unwritable gitdir `index-compose.sh` reaches the relay write carrying
     exactly that report, and discards it. `index-sync-post.sh` reaches it the
     same way through its `failed` branch.

     **`additionalContext`, not `systemMessage`.** The subagent-confinement
     probe measured that a subagent's `systemMessage` reaches nobody at all — it
     appears in that subagent's own JSONL and nowhere else, and the model never
     quoted it — while `additionalContext` arrives as a system-reminder and the
     model narrated it unprompted. The value of this signal is that the actor
     can carry the fact into its own reply, which is the only path out of a
     subagent, so it needs the model's channel. Appended *after* the write,
     since it describes the staging failure and must not itself be staged.
     Imperative wording is right here: the no-actionable-phrases rule governs
     deny channels, and this is a directive channel whose point is that the
     agent acts.

     Also in this slice, because it is the same failure class one line below the
     read slice 4 made tolerant:
     **`gitlore_relay_drain`'s `rm -f` still propagates** on an unwritable
     gitdir, contra the function's own "Always returns 0", and both
     PostToolBatch hooks call the drain bare. Reachable through
     `index-sync-post.sh`, where an unwritable gitdir makes the frontmatter sync
     fail, produces the `failed` report, and then the drain kills the hook
     before it emits it.

     The fix is `rm -f "$marker" || true`, and it costs something, which is why
     it needs a companion rather than a one-token edit: with the reads already
     tolerant, that token makes `-type f` un-pinned — the frozen case
     `an unkeyed run survives a non-file squatting on a marker name` stops
     discriminating it, measured. The companion restores the coverage by pinning
     `-type f` for what it is actually for rather than for an abort it will no
     longer cause.

     - `a failed relay write tells the subagent it was not staged` in
       `tests/cc_hook_index_compose.bats` — over slice 4's directory-squat
       fixture, a keyed compose run; asserts the hook still exits 0, its own
       `systemMessage` still carries the compose report, and its
       `additionalContext` now carries the not-staged line. Extract each channel
       with `jq -r` and assert the channel is not the literal `null` before
       refuting anything on it.
     - `an unkeyed run leaves a non-marker alone` in
       `tests/cc_hook_index_compose.bats` — the companion. Over the same squat,
       an unkeyed run; asserts the squat directory still exists afterwards and
       no framing line names it. This is what `-type f` is for: not framing and
       not removing something that is not a marker.
     - `the drain survives a gitdir it cannot write` in `tests/index_sync.bats`
       — a marker present, the gitdir made unwritable, a caller in the hooks'
       own `set -euo pipefail` shape; asserts the caller reaches its own report.
       Skip when running as root, as the neighbouring permission cases do.

     The `index-sync-post.sh` half of the first case stays unpinned, as slice
     4's `|| true` on that hook already is: nothing in either suite squats that
     hook's marker path, and both were measured to red nothing when removed. The
     fix lands in both hooks regardless — the defect is identical and leaving
     one standing is worse than an unpinned fix.

---

## Phase 4: Design record and changelog (type: general)

- Item 4.0: `docs/references/index-authoring-sync.md` — narrow the per-batch
  baseline invariant to per-agent. Requirements: FR-C. Depends on: Item 2.1,
  Item 3.1. Model: opus

  Added at the Phase 2 checkpoint, not present in the runbook as proofed. Item
  2.1's slice 4 code review found this node still asserting the invariant Item
  2.1 falsified, and no Phase 4 item covered it: Items 4.1-4.3 reach
  `git-hooks-and-entry-points.md`, `design.md`, `decisions.md` and the
  changelog, so this is the one place the plugin's shipped documentation still
  describes the unkeyed behaviour.

  The passage (`:45-57`) says "every baseline is per-batch", and that "the
  post-hook drops the stash at every batch end, even one where the index went
  untouched, so a pre-image can never become a *second* batch's baseline". Both
  halves are now false. Baselines are keyed per (agent, batch): a batch resolves
  only the name its own agent stashed, so the drop bounds that agent's own
  stashes and nobody else's. The claim it should make instead is the one
  `index-sync-pre.sh:54-58` states — a pre-image can never become another
  agent's baseline, and one stranded by a subagent that died mid-batch is
  consumed by nothing, because an agent id is not reused.

  Sequenced after Item 3.1, not straight after Item 2.1: the relay adds a marker
  with the same keyed lifecycle to the same hooks, so the paragraph is written
  once against the final shape. State current truth in the present tense — this
  is not a correction of a previous version.

- Item 4.1: `docs/references/git-hooks-and-entry-points.md` — record the
  commit-path composition decision as a new numbered decision with its rejected
  alternatives. Requirements: FR-E. Depends on: Item 1.1, Item 1.2. Model: opus

  **Also carries the subagent-confinement evidence.** Item 3.1's slice 1 code
  review removed a citation of `subagent-hook-output-probe.md` from
  `scripts/lib/index-sync.sh`: shipped source must not cite `plans/`, which is
  prospective and gets swept, and it must not cite `memory/` either, which
  reaches the tree through a submodule gitlink and is not distributed. The
  measurement that justifies the whole relay — a hook firing inside a subagent
  has both output channels confined to that subagent, CC 2.1.261 — therefore has
  no shipped home. Give it one here, under its own `D<n>`, and back-fill that id
  into the `gitlore_relay_*` comment blocks in `scripts/lib/index-sync.sh`,
  which currently say only "(measured under CC 2.1.261)". Two ids are in play in
  this phase, so re-derive both.

  The node is 340 lines, so the addition stays under the 400-line cap. Take the
  next free `D<n>` — `scripts/check-docs-links.py` blocks a `duplicate-decision`
  and an `undefined-decision`, so the number must be new and must be argued here
  and concluded once in `docs/decisions.md` (Item 4.2). The highest in use
  across `docs/decisions.md` and `docs/references/` at plan time is `D49`, so
  `D50`; re-derive rather than trust that, with
  `grep -oh 'D[0-9]\+' docs/decisions.md docs/references/*.md | sort -u -t D -k2 -n | tail -1`.

  **The gate does not run between this item and 4.2.** A decision argued in a
  node and concluded nowhere in the decisions index is what
  `scripts/check-docs-links.py` blocks on as `unstubbed-decision`, so 4.1 alone
  leaves the tree red by construction. Run `python3 scripts/check-docs-links.py`
  after 4.2, and land the two in one commit.

  The node enumerates its decisions twice — the title line
  (`# Git hooks and entry points — decisions D16, D20, D46`) and the
  `## Decisions — D16, D20, D46` heading — and `enumeration-drift` re-derives
  both from the bodies, so append `D50` to both headings, or the run after 4.2
  blocks. The `**D50 — …**` body goes under `## Decisions`; the rejected
  alternative goes under `## Rejected alternatives` at the node's close, which
  is where the index's *Rejected* line points.

  The decision states: the commit path composes before it commits, scoped to
  `dirty = 1` only, with a `gitlore_compose_check` refusal reported and not
  fatal, a pin refusal aborting, and a write failure aborting. Its argument
  carries the three reasons Phase 1 encodes — the carrier is what the tier's
  remote receives, so a stale one *ships*; composing a clean store manufactures
  a dirty state no approved summary covers, which is what keeps the FR11
  boundary intact; and the two halves of the refusal rule are not
  interchangeable. A `gitlore_compose_check` refusal withholds a projection and
  destroys nothing, so committing the carrier as it stands is correct. A
  `gitlore_compose_check_pins` refusal is the opposite: report and proceed, and
  the commit's own `git -C "$mempath" add -A` adopts the moved gitlink, removing
  the very condition the check refused on — so the next compose projects root's
  older text over the carrier with nothing left to refuse,
  `gitlore_sync_tiers_to_live` commits that inside the tier, and `pre-push`
  ships it to the tier's own remote. The approved upstream fact is destroyed one
  commit after the warning, so the pin case aborts (Item 1.2).

  **A successful compose on the commit path stays silent**, and that is an
  argued point rather than an omission. On rc 0 the captured result — one line
  per carrier actually rewritten — is discarded, so a commit that repairs a
  stale carrier says nothing to anyone. The counter-argument is real: a
  *non-empty* result on the commit path means the in-session compose was missed,
  which is the hole this job exists to close, and one `[ -n "$compose_result" ]`
  branch would say so on stderr. It is left silent because the in-session
  `PostToolBatch` report is the intended surface for that news, and duplicating
  it at commit time puts a line on every commit that repairs anything — most of
  which the session has already seen.

  Its `Rejected:` line takes two entries:
  **a refusal that instructs the agent to run compose** — rejected because
  composition needs no judgement, so making the agent run it is overhead the
  harness should absorb (NFR4) — and
  **reporting an off-pin tier and committing through it**, rejected because the
  commit's own `add -A` adopts the moved gitlink, so the report is followed at
  the next compose by exactly the silent overwrite it warned about.

- Item 4.2: `docs/design.md` and `docs/decisions.md` — conclude the new
  decision. Requirements: FR-E. Depends on: Item 4.1. Model: opus

  Two edits, one per file, in one item because they are two surfaces of one
  prose artifact:

  - `docs/design.md` §Architecture, the **Git hooks and entry points** bullet
    (the fourth bullet of §Components) — one clause added to the existing
    sentence about `pre-commit`, saying it composes the store before committing
    so the carrier a tier's remote receives matches the root index.
  - `docs/decisions.md`, the **Git hooks and entry points** group — one
    `- **D<n>** — …` conclusion stub beside D16/D20/D46, and Item 4.1's two
    rejected alternatives appended to the group's existing `*Rejected:*` line.

  **Line budget.** The conclusion lines live in `docs/decisions.md` (about 130
  lines) and the hub is under 280, both against the uniform 400-line cap
  `scripts/check-docs-links.py` applies to every file under `docs/`, so the ~4
  lines fit without touching the checker. Measure after `just format-docs`, not
  before.

- Item 4.3:
  `docs/changelog/2026-09-06-the-commit-path-composes-before-it-commits.md` and
  `docs/changelog.md` — the changelog's two required surfaces. Requirements:
  FR-E. Depends on: Item 4.2. Model: sonnet

  An entry file under `docs/changelog/` carrying what changed and why, and its
  newest-first summary bullet at the top of `docs/changelog.md`.
  Design-significant only: the commit-path composition decision and the
  per-agent keying that made the subagent relay possible; not the test counts.
  The date in the filename is the day the entry lands, not the day this runbook
  was written — rename if execution slips past it.

  Both surfaces sit under `docs/`, so both are subject to the same
  `oversized-file` cap Item 4.2 measures against. `docs/changelog.md` is well
  under the cap, so a summary bullet has room; the entry file is new and starts
  near zero.

---

## Gate

Run `just precommit` with `run_in_background: true`. The 10-minute Bash cap
bounds only a foreground wait; a background task has no duration cap and runs
across turns in the main session, so the run completes, records the sentinel,
and its completion notification carries the verdict
(`background-run-timeout-probe.md`, this directory, including the observed
main-session run). Only if the run dies fall back to `just lint`,
`just test-integration` and `just test-unit` as three sequential calls, and say
that the sentinel was not recorded.

Phase 4 also needs `python3 scripts/check-docs-links.py`, which is what enforces
`duplicate-decision`, `unstubbed-decision`, `delegation-drift` and
`oversized-file` on the edits Items 4.1 and 4.2 make. Run it after Item 4.2,
never between 4.1 and 4.2: a decision argued in the node with no conclusion yet
in the decisions index blocks by design.
