# Outline — index-edit propagation

Job: act on `inbox/brief-index-edit-propagation-findings.md`. Triage in
`classification.md`; the evidence settling findings 2 and 3 is in
`root-cause.md`. This outline covers only what remains executable.

## Scope

Four changes, one already applied. All are in gitlore's own scripts plus the
design record. No change to any tier store, no memory-content edit.

| # | change | status |
|---|---|---|
| A | compose's `additionalContext` no longer denies that it re-texts carrier lines | applied (`c0963f5`) |
| B | the commit path composes before it commits | to do |
| C | the pre-image and compose-stamp paths are keyed per agent | to do |
| D | a subagent's compose and index-sync reports are relayed to the parent | to do |

## A — the false compose sentence (done)

`scripts/lib/index-compose.sh:718`, one string. Was "Composition moves or drops
lines; it never changes a line's text"; now states that carrier lines are
placed, dropped **and re-texted** from the root index, and that root's own lines
are only reordered. Grounded in `gitlore_compose_down`, which picks root's
bullet text for every path root carries, and in D29/D36, which scope "never its
text" to the root index.

`just lint` clean; `tests/index_compose.bats` +
`tests/cc_hook_index_compose.bats` 78 passed. No test asserted the old sentence,
and none asserts the new one — item B's tests are where the sentence's claim
gets locked in behaviourally.

## B — compose in the commit path

**The hole.** `gitlore_compose` has three callers: `session-start.sh`, the
`PostToolBatch` hook, and `add-tier-batch.sh`. The commit path is not among
them. (Resolve calls `gitlore_compose_up`, the tier→root direction — a different
function from the downward composition this item is about.) A carrier left stale
by a missed in-session compose self-heals at the next SessionStart but **ships**
if a memory commit lands first, and the carrier is what the tier's remote
receives.

**The change.** `gitlore_sync_memory_to_live` (`scripts/lib/resolve.sh:871`)
composes before it commits. That one function is the shared body behind both
commit entry points — the `pre-commit` hook (`scripts/git-hooks/pre-commit:68`)
and `commit-memory.sh:66` — so every commit path gets it from one edit.

Ordering and boundaries, all load-bearing:

- **After the stale-merge guard, after the dirty check, before
  `gitlore_sync_tiers_to_live`.** Compose writes carrier files *inside* the
  tiers, so it must precede the tier commits or their gitlinks pin the
  pre-compose content — the same one-behind lag the existing tier-first ordering
  exists to prevent.
- **Only when `dirty = 1`.** Composing a clean store can *create* a dirty state
  the user never approved a summary for, and the gate would then refuse the
  commit for a change the agent did not make. A store whose committed carrier
  already diverges from its committed root index is left to SessionStart, whose
  compose rides the next commit that has a summary. This is what keeps FR11's
  boundary intact: the carrier is a projection of root index lines the approved
  summary already covered, never new content.
- **A refusal is reported, not fatal.** `gitlore_compose` returns 1 when
  `gitlore_compose_check` or `gitlore_compose_check_pins` refuses — the off-pin
  case exists precisely because projecting root's older text over an unadopted
  carrier would destroy approved upstream facts (D31, D36). Committing that
  carrier as-is is correct. Report and continue.
- **A write failure (rc 2) aborts the commit.** A half-written carrier must not
  be committed.
- **Plain text on the hook's own channel**, via `gitlore_say_for_agent_or_user`
  — not `gitlore_compose_and_report`, whose output is `PostToolBatch` JSON and
  is meaningless to git. **On stderr**, matching every other
  `gitlore_say_for_agent_or_user` call in `scripts/lib/resolve.sh`, including
  the ones on success returns: the helper always prints to stdout and the stream
  is the call site's choice, so without the redirect the advisory interleaves
  with git's own output and lands in anything that captures the function's
  stdout.

**Files:** `scripts/lib/resolve.sh` (the compose call and its reporting);
`scripts/lib/resolve.sh` must source or already have `index-compose.sh` in scope
— it sources it at line 11, so no new dependency.

**Tests:** `tests/commit_memory.bats` and
`tests/git_hook_memory_pre_commit.bats` are the homes. The red case is a store
whose root index and carrier disagree, committed through each entry point,
asserting the committed carrier matches what composition produces — it must fail
against unchanged code. The SUT already exists, so that red is a failed
assertion rather than a missing symbol.

Two further cases, each with its induction named so the red comes from the cause
under test:

- **The off-pin refusal** (commit proceeds, refusal reported). Fixture: an
  active, materialized tier whose worktree HEAD differs from the gitlink the
  memory store's **index** records — `git -C memory rev-parse ":$tier"`, not
  `HEAD:$tier`, which is what `gitlore_compose_check_pins` reads and why. Reach
  it with a commit inside the tier worktree that is never staged in memory's
  index. The tier must not be mid-merge, or `check_pins` emits its other message
  instead.
- **The rc-2 abort.** Reuse the induction already proven at
  `tests/index_compose.bats:920` — `chmod a-w` on the carrier's directory so
  `gitlore_compose_write`'s temp file (or its `mv`) fails — restoring the mode
  immediately after `run`. Add the
  `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"` guard that
  `tests/index_sync.bats:356` uses and that the existing compose case lacks.

## C — per-agent pre-image and compose-stamp paths

**The race.** `gitlore_index_preimage_file` and `gitlore_compose_stamp_file`
(`scripts/lib/index-sync.sh:94,102`) each return one fixed path in the memory
gitdir. Parent and subagent batches share them, `index-sync-pre.sh` skips
re-baselining when a file is already present, and every `PostToolBatch` consumer
`rm -f`s unconditionally. Observed in the reporting session: the subagent's Edit
wrote the baseline at 22:10:47.696 and the parent's Bash pre-hook 243 ms later
found it present and left it. Harmless in that ordering; the mirror — a parent
batch ending between a subagent's pre-hook and its post-hook — consumes the
subagent's baseline and strands its edit silently.

**The change.** Suffix both paths with the payload's `agent_id`, which hook
stdin carries only when the hook fires from within a subagent. Absent on the
main thread, so the existing filenames stay the main thread's and nothing
migrates. Read `agent_id` specifically, never `agent_type` — that one also
appears on the main thread of an `--agent` session.

**No hook parses `agent_id` today**: the string appears nowhere in `scripts/`,
so all four consumers below gain a new payload read rather than passing a value
already in hand.

**Files:** `scripts/lib/index-sync.sh` (both helpers take an agent id);
`scripts/cc-hooks/index-sync-pre.sh`, `index-sync-post.sh`, `index-compose.sh`,
`add-tier-batch.sh` (each reads `agent_id` from its payload and passes it).
`add-tier-batch.sh` also drops the compose hook's baseline — that drop must
target the same keyed path. `index-sync-pre.sh` additionally carries the comment
this change falsifies — "Each post hook removes its own file at batch end (even
when nothing was touched), so an existing one here always belongs to the batch
in flight" — which is the invalidated assumption itself and has to be rewritten,
not left standing.

**Cleanup:** a subagent that dies mid-batch strands a keyed file. Bound it the
way the current code bounds a stale pre-image: state the residual in a comment
rather than adding a sweeper, since a stranded file is consumed and deleted by
the next batch of that same agent id and an agent id is not reused.

**Tests:** `tests/index_sync.bats` for the keying; a
`cc_hook_index_compose.bats` case driving a pre-hook with `agent_id` set and a
post-hook without it, asserting the main-thread baseline survives.

## D — relay a subagent's reports to the parent

**Why it is needed**, settled empirically rather than assumed: a hook firing
inside a subagent has both its `systemMessage` and its
`hookSpecificOutput.additionalContext` confined to that subagent. Probe and
control in `subagent-hook-output-probe.md` (CC 2.1.261) — the parent transcript
carries zero `hook_*` attachments while the subagent's own JSONL carries all
four, and the control run with no subagent surfaces both channels normally. So
when a subagent's edit to the root index triggers composition, the compose runs
and its report reaches neither the parent's context nor the user, which is what
happened in the reporting session. The parent's only possible view is whatever
the subagent chooses to narrate — model-mediated, not a mechanism.

**The change.** A hook whose payload carries `agent_id` writes the report it
just produced to a marker in the memory gitdir, keyed by that agent id: a sixth
untracked `rev-parse --git-path gitlore-…` file, beside `gitlore-nudged`,
`gitlore-merge-state`, `gitlore-index-preimage` and `gitlore-compose-stamp`. The
next parent-side run — no `agent_id` — globs the markers, folds their contents
into its own report, and removes them. `session-start.sh` drains the same way,
so a marker outliving its session is not lost.

- **Both reports, one helper.** The confinement is a property of the event, not
  of the script, so `index-sync-post.sh`'s report is relayed on the same
  mechanism as the compose hook's. One marker helper serves both.
- **Each folded-in block is attributed to its agent**, so an interleaved session
  stays legible; the cost is one line of framing per block.
- **In addition to, not instead of.** The subagent still emits its own report:
  it is the actor, and a blind agent goes looking rather than waiting — measured
  at re-verification after 91% of silent commits. Suppressing the subagent's
  copy to avoid double-reporting buys nothing and costs the actor its
  confirmation.

**Depends on C**, which is what puts `agent_id` in these hooks' hands. D is
unimplementable before it.

**Files:** `scripts/lib/index-sync.sh` (the marker path helper, beside C's two);
`scripts/cc-hooks/index-compose.sh` and `index-sync-post.sh` (write when keyed,
drain when not); `scripts/cc-hooks/session-start.sh` (drain).

**Tests:** `tests/cc_hook_index_compose.bats` — a keyed run writes a marker and
emits nothing on the parent-facing target; an unkeyed run drains it and carries
the attribution; a SessionStart drain case.

## Design record

One decision, in `docs/references/git-hooks-and-entry-points.md`: the commit
path composes before it commits, with the dirty-only scope and the
refusal-is-not-fatal rule, and its `Rejected` line takes "a refusal that
instructs the agent to run compose" — rejected because composition needs no
judgement, so making the agent run it is overhead the harness should absorb.
Summarize in `docs/design.md` §Architecture under Git hooks and entry points,
where the existing block lists D16/D20/D46 and a new decision means a new
bullet. The changelog is two surfaces, both required: an entry file under
`docs/changelog/YYYY-MM-DD-slug.md` and its newest-first summary bullet in
`docs/changelog.md`.

`docs/design.md` sits at exactly its 400-line cap, which is already the state a
cap stops signalling from: the next line added anywhere breaks the build, and
that reads as a tooling failure rather than as "this document is due to be
split". So **the split decision comes first**, as a decision put to my human
partner — not word-replacement with the split as a fallback, which spends prose
to keep a number down and borrows against the split rather than replacing it. A
bounded overage on one cohesive document is also a legitimate outcome where
splitting would cost the reader more than the overage does.

## Out of scope

- **Finding 2.** No defect. `originSessionId` is unchanged on all 13 files and
  the brief's cited file has never carried the field. The only real effect is a
  `modified:` restamp, which the brief itself calls correct — and which is
  conditional rather than automatic: the stamper no-ops on a non-`.md` file, a
  path that is not a lexical prefix match under the memory root, content not
  opening with `---` at byte 0, a `rewriteHazard`, an inline `metadata:`
  mapping, or a failed faithfulness re-parse, and a `Bash` write never stamps at
  all.
- **A dirty-carrier query surface.** B makes the question moot at the only
  moment its answer matters.
- **Backfilling descriptions that never matched their index lines.** The sync
  keys on a *changed* hook by design; a backfill is a separate capability.
