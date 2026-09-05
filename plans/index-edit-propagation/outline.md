# Outline — index-edit propagation

Job: act on `inbox/brief-index-edit-propagation-findings.md`. Triage in
`classification.md`; the evidence settling findings 2 and 3 is in
`root-cause.md`. This outline covers only what remains executable.

## Scope

Three changes, one already applied. All are in gitlore's own scripts plus the
design record. No change to any tier store, no memory-content edit.

| # | change | status |
|---|---|---|
| A | compose's `additionalContext` no longer denies that it re-texts carrier lines | applied, uncommitted |
| B | the commit path composes before it commits | to do |
| C | the pre-image and compose-stamp paths are keyed per agent | to do |

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

**The hole.** `gitlore_compose` has four callers: `session-start.sh`, the
`PostToolBatch` hook, `add-tier-batch.sh`, and resolve. The commit path is not
among them. A carrier left stale by a missed in-session compose self-heals at
the next SessionStart but **ships** if a memory commit lands first, and the
carrier is what the tier's remote receives.

**The change.** `gitlore_sync_memory_to_live` (`scripts/lib/resolve.sh:871`)
composes before it commits. That one function is the shared body behind the
`pre-commit` hook, `commit-memory.sh` and resolve, so every commit path gets it
from one edit.

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
  is meaningless to git.

**Files:** `scripts/lib/resolve.sh` (the compose call and its reporting);
`scripts/lib/resolve.sh` must source or already have `index-compose.sh` in scope
— it sources it at line 11, so no new dependency.

**Tests:** `tests/commit_memory.bats` and
`tests/git_hook_memory_pre_commit.bats` are the homes. The red case is a store
whose root index and carrier disagree, committed through each entry point,
asserting the committed carrier matches what composition produces — it must fail
against unchanged code. Add the off-pin refusal case (commit proceeds, refusal
reported) and the rc-2 case (commit aborts).

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
migrates.

**Files:** `scripts/lib/index-sync.sh` (both helpers take an agent id);
`scripts/cc-hooks/index-sync-pre.sh`, `index-sync-post.sh`, `index-compose.sh`,
`add-tier-batch.sh` (each reads `agent_id` from its payload and passes it).
`add-tier-batch.sh` also drops the compose hook's baseline — that drop must
target the same keyed path.

**Cleanup:** a subagent that dies mid-batch strands a keyed file. Bound it the
way the current code bounds a stale pre-image: state the residual in a comment
rather than adding a sweeper, since a stranded file is consumed and deleted by
the next batch of that same agent id and an agent id is not reused.

**Tests:** `tests/index_sync.bats` for the keying; a
`cc_hook_index_compose.bats` case driving a pre-hook with `agent_id` set and a
post-hook without it, asserting the main-thread baseline survives.

## Design record

One decision, in `docs/references/git-hooks-and-entry-points.md`: the commit
path composes before it commits, with the dirty-only scope and the
refusal-is-not-fatal rule, and its `Rejected` line takes "a refusal that
instructs the agent to run compose" — rejected because composition needs no
judgement, so making the agent run it is overhead the harness should absorb.
Summarize in `docs/design.md` §Architecture under Git hooks and entry points;
changelog entry for the shipped behaviour change.

`docs/design.md` is at its 400-line cap, so the summary must fit by replacing
words rather than adding lines, or the split decision comes first.

## Out of scope

- **Finding 2.** No defect. `originSessionId` is unchanged on all 13 files and
  the brief's cited file has never carried the field; the only real effect is a
  `modified:` restamp the harness does on Edit-tool writes, which the brief
  itself calls correct.
- **Surfacing a subagent-side compose report to the parent.** The delivery is
  the harness's: in the reporting session the compose ran inside the subagent
  and its report reached neither context. A mitigation (write a marker when
  `agent_id` is set; the next parent-side hook reports it) is only worth
  building if no hook output survives a subagent batch at all — one `claude -p`
  probe with a trivial subagent edit settles it. Not started, and no code here
  presupposes either answer. C is independent of it and worth having regardless.
- **A dirty-carrier query surface.** B makes the question moot at the only
  moment its answer matters.
- **Backfilling descriptions that never matched their index lines.** The sync
  keys on a *changed* hook by design; a backfill is a separate capability.
