# Deliverable Review: index-edit-propagation

**Date:** 2026-09-12 **Methodology:** docs/design.md §6.8 "Deliverable review"

Baseline: `outline.md` (§B–D, §Design record) as amended by `runbook.md` (FR-B,
FR-F, FR-C, FR-D, FR-E; "as executed" / "as amended" notes take precedence).
Range `b6dbe92..HEAD`, excluding the unrelated commits `3d50a1f` (decisions
index leaves the hub), `c2e7950` (per-recipe gates) and `ae54c1b` (precommit
sign-off); the post-run `951b83a` (node split) and `8523b47` (atomic relay
install) are in scope.

Layer 1 ran (deliverables > 2000 lines) as three opus partitions:
`deliverable-review-code.md`, `deliverable-review-test.md`,
`deliverable-review-prose.md`. Layer 2 ran in the main session and reproduced
the two Critical findings with probes before rating them.

## Inventory

| Type | File | + / − |
|---|---|---|
| Code | `scripts/lib/resolve.sh` | 186 / 0 |
| Code | `scripts/lib/index-sync.sh` | 260 / 4 |
| Code | `scripts/lib/index-compose.sh` | 17 / 0 |
| Code | `scripts/cc-hooks/index-compose.sh` | 58 / 3 |
| Code | `scripts/cc-hooks/index-sync-post.sh` | 66 / 2 |
| Code | `scripts/cc-hooks/index-sync-pre.sh` | 17 / 5 |
| Code | `scripts/cc-hooks/add-tier-batch.sh` | 17 / 3 |
| Code | `scripts/cc-hooks/session-start.sh` | 29 / 0 |
| Test | `tests/index_sync.bats` | 807 / 1 |
| Test | `tests/commit_memory.bats` | 415 / 0 |
| Test | `tests/cc_hook_index_compose.bats` | 373 / 5 |
| Test | `tests/resolve_recovery.bats` (new) | 307 / 0 |
| Test | `tests/git_hook_pre_commit.bats` | 185 / 0 |
| Test | `tests/index_compose.bats` | 158 / 4 |
| Test | `tests/cc_hook_session_start.bats` | 116 / 0 |
| Test | `tests/cc_hook_add_tier.bats` | 64 / 2 |
| Test | `tests/helpers/setup.bash`, `push_memory.bats`, `tier_lockstep.bats` | 12 / 2 |
| Human docs | `docs/references/git-hooks.md` (new, split) | 189 / 0 |
| Human docs | `docs/references/memory-entry-points.md` (renamed) | 13 / 116 |
| Human docs | `index-authoring-sync.md`, `index-composition.md`, `cc-platform.md`, `session.md`, `commit-gate.md`, `merge-state-recovery.md`, `tier-stores.md` | 131 / 73 |
| Human docs | `docs/decisions.md`, `docs/design.md` (D50, D51, split) | in-range hunks |
| Human docs | `docs/changelog.md` + two 2026-09-11 entries | 113 / 0 |
| Agentic prose | `CLAUDE.md` (hunk from `ca41cbe`) | in-range hunk |

Conformance summary: every item and slice the runbook names was delivered, and
every named test case exists and asserts what the runbook specifies (test
partition, §Coverage). The defects are in behaviour the runbook's own premises
got wrong: same-event hooks run in parallel, and the new pin guard cannot tell
gitlore's own half-landed tier commit from a tier that moved behind root's back.

## Critical Findings

### C1 — The pin guard permanently refuses the retry of a half-landed commit

- **Where:** `scripts/lib/resolve.sh:1000-1021` (pin guard) with `:1091-1100`
  (tier commit, then memory `add -A`); message at
  `scripts/lib/index-compose.sh:349`.
- **Requirement:** FR-F's guard, against the transparent-retry contract in
  `scripts/cc-hooks/memory-commit-batch.sh:103-107` ("a locked repo … and an
  in-flight merge are expected transient conditions … the next PostToolBatch
  retries transparently — no agent action, no lost approval").
- **Mechanism:** `gitlore_sync_tiers_to_live` commits inside each dirty tier;
  only the later memory `add -A` stages the moved gitlink. Anything that stops
  the run in between — an `index.lock` on memory, a tier `live` advance failing
  for a non-divergence reason (e.g. `live` checked out by another session), a
  second tier's commit failing, Ctrl-C — leaves the tier HEAD ahead of the pin
  memory's index records, with the approved summary kept. The retry now aborts
  before reaching `add -A`.
- **Reproduced** (Layer 2, single-case bats probe driving
  `scripts/commit-memory.sh`; a tier `post-commit` hook takes memory's
  `index.lock`, the lock is then cleared and the commit retried): at HEAD the
  retry exits 1 with "ahead of the pin … There is no automatic remedy: inspect
  and stage the gitlink by hand, or return the tier to the pin, which discards
  the commits it carries ahead of it." The identical probe against the `b6dbe92`
  scripts retries to exit 0.
- **Impact:** a transient lock becomes a permanent block on every memory commit
  in the session, while the batch hook tells the agent "no action is needed".
  The one remedy that moves anything by itself discards the tier commit the user
  approved. Before Item 1.2 the retry adopted the move and completed.

### C2 — The relay assumes same-event hooks run in sequence; they run in parallel

- **Where:** `scripts/lib/index-sync.sh` `gitlore_relay_write` (read → merge →
  write the shared `"$marker.tmp"` → `mv`) and `gitlore_relay_drain` (find → awk
  → awk → rm); `hooks/hooks.json` puts `index-sync-post.sh` and
  `index-compose.sh` on the same `PostToolBatch`. The false premise is written
  down at `scripts/lib/index-sync.sh:300` ("not sequential the way hooks within
  one session are") and in slice 2.5's case comment
  (`tests/cc_hook_index_compose.bats:357`, "in that order").
- **Requirement:** FR-D — reports produced inside a subagent reach the parent.
- **Grounding:** code.claude.com/docs/en/hooks: "All matching hooks run in
  parallel."
- **Reproduced** (Layer 2 shell probe against the real library, 200 iterations
  each; the code and test partitions ran independent probes with the same shape
  of result):
  - two concurrent `gitlore_relay_write` for one agent id — both reports merged
    112, **one report lost 86**, **torn marker 2**; 88 losses were reported to
    the subagent as a failed write, the rest silent;
  - two concurrent unkeyed drains over one marker —
    **the block relayed twice 144**, **an empty framed block 51**, exactly once
    5.
- **Impact:** in the ordinary case slice 2.5 was written for — a subagent edits
  `MEMORY.md` with a tier mounted, so both hooks report — the parent regularly
  receives only one of the two reports, occasionally a spliced body. On the
  parent side, both hooks drain on the same batch and the user sees each relayed
  block twice.
- **Why the suite is green:** every relay case drives the hooks one after the
  other (Major M6).

## Major Findings

### M1 — The drain can delete a report written between its read and its `rm`

- **Where:** `scripts/lib/index-sync.sh` `gitlore_relay_drain`, the two
  `_gitlore_relay_*block` reads, then `rm -f "$marker"` and
  `rm -f "$marker.tmp"`.
- **Requirement:** FR-D. **Verdict:** plausible, from the code; not probed.
- A subagent is running concurrently with the parent (the premise of FR-C). Its
  write can `mv` a merged marker into place after the drain's reads and before
  the drain's `rm`. The drain then removes the newer report unread, and the
  write returned 0, so nobody is told. The `.tmp` removal can also unlink a temp
  another writer is still filling. Fix direction: claim with a rename before
  reading.

### M2 — The parent-side drain only runs on a batch that changed the index

- **Where:** `scripts/cc-hooks/index-compose.sh` (the drain after
  `[ -n "$index_touched$manifest_touched" ] || exit 0`) and
  `scripts/cc-hooks/index-sync-post.sh` (after the `cmp -s` early exit).
- **Requirement:** FR-D ("reach the parent session").
- The runbook records this (Item 3.1 slice 2) and names SessionStart as the
  backstop, and `index-authoring-sync.md` documents it, so the delivery conforms
  to the runbook. The requirement is still not met for the case the outline was
  written about. The parent batch that dispatched the subagent has no baseline:
  `index-sync-pre.sh` matches only `Write|Edit|Bash`. The report therefore waits
  for a parent edit to the root index or for the next SessionStart — a different
  session or a context reset, where it is framed under an agent id that session
  never saw.

### M3 — Relay markers are keyed by agent id only, so another session can drain them

- **Where:** `gitlore_relay_marker_file` and `gitlore_relay_drain`
  (`scripts/lib/index-sync.sh`); `scripts/cc-hooks/session-start.sh` drain.
- **Requirement:** FR-D.
- Every session in the same checkout shares the memory gitdir. Peer sessions are
  routine here, and a `/compact` with a background subagent live does the same
  thing. Any session's unkeyed batch or SessionStart folds and removes every
  `gitlore-relay-*`. The report lands in the wrong conversation, and the parent
  that dispatched the subagent never gets it. Nudge markers already key on
  `session_id`.

### M4 — The ahead-of-pin remedy "stage the gitlink by hand" is the overwrite the guard exists to stop

- **Where:** `scripts/lib/index-compose.sh:349`; the dependency is
  `scripts/lib/resolve.sh` `gitlore_adopt_recovered_merge`'s up-projection
  failure message ("the next gate refuses the tier instead").
- **Requirement:** FR-F, NFR2.
- `resolve.sh`'s own header for `gitlore_adopt_recovered_merge` states that
  staging a tier ahead of its pin without composing up "turns [the refusal] into
  a silent overwrite". The refusal line offers exactly that as its first remedy,
  with no command and no mention of composing up.
- **Scenario:** a recovered merge whose up projection fails leaves the gitlink
  unstaged → the next commit aborts with this line → the agent stages by hand →
  the pin guard passes and `gitlore_compose` projects root's older text over the
  carrier → the tier commit and pre-push publish it.
- Under C1 the same instruction happens to be safe, since that carrier was
  already composed. The message cannot tell the two cases apart.

### M5 — D50's adoption invariant is false for the take path, and two nodes disagree

- **Where:** `docs/references/git-hooks.md:159-166` against
  `docs/references/tier-stores.md:162-166` and `scripts/lib/resolve.sh`
  `gitlore_adopt_tier_into_root`.
- **Requirement:** FR-E.
- D50 says every path that adopts a tier ahead of its pin composes up and stages
  the pair, or stages nothing. `gitlore_adopt_tier_into_root` — which the
  recovery's header names as "the precedent" — still stages and commits
  bookkeeping when `gitlore_compose_up` fails, and so does the merge
  continuation. Which side is correct is a design call: narrow D50, or change
  the take's failure arm.

### M6 — No test runs the PostToolBatch hooks concurrently

- **Where:** `tests/cc_hook_index_compose.bats:357-411` (slice 2.5 case) and the
  unkeyed-drain cases in that file and `tests/index_sync.bats`.
- **Requirement:** FR-D test coverage.
- The parent/subagent interleavings for FR-C are correctly deterministic,
  because the two agents' files are disjoint. The FR-D race is between two
  writers of one file, and a fixed sequential order can only exercise the merge
  logic. Replacing the `mv` install with `cat tmp > marker`, or reordering the
  merge's read, still passes every case.

### M7 — `CLAUDE.md`'s gate-file fallback reads green on a docs-only failure

- **Where:** `CLAUDE.md` §Testing, gate paragraph (hunk from `ca41cbe`).
- **Requirement:** project convention (the gate before every commit).
- `precommit` also runs `format-docs`, `check-memory-hygiene.py`,
  `check-docs-links.py` and `check-version`, and none of them writes a gate
  file. A docs-only edit that breaks the link check stops `precommit` before
  `lint`/`test-*`. The four existing gate files then still postdate every gated
  input, and a subagent reads a pass. The working tree is in exactly that state
  now: the link check exits 1 on untracked `docs/plans/` and `docs/superpowers/`
  oversized files.
- Also: validity is a content hash, not an mtime; the gates path is
  per-worktree; and the "only if the run dies" fallback omits
  `check-distribution` and the four uncached checks.
- Overlaps the open handoff decision on rewriting this paragraph.

## Minor Findings

**Commit path (`scripts/lib/resolve.sh`)**
- The approval is left stale when the per-tier recovery loop or a successful
  compose writes and a later step fails. The "No restamp … this writes nothing"
  comment no longer holds for the run as a whole, since Item 1.3 put writes in
  the loop above it.
- `gitlore_adopt_recovered_merge` has no short-circuit when the enclosing index
  already records the tier's HEAD. A continuation killed after its bookkeeping
  commit can therefore compose up again and revert a root-index edit to that
  tier's lines. The window is narrow. Plausible, not probed.
- The printed `git -C %s add -- MEMORY.md %s` remedy is unquoted, so it is not
  runnable on a spaced project path. No spaced-root case covers the adoption.

**Stale or wrong comments**
- `scripts/lib/index-sync.sh`: "the redirect below is the single write, so a
  failed open leaves nothing on disk" is stale since `8523b47`.
- `scripts/lib/index-compose.sh:297`: "only gitlore_compose calls it" — the
  commit path calls `gitlore_compose_check_pins` too.
- `tests/index_sync.bats:1118` and `tests/cc_hook_index_compose.bats:416-455`
  describe the squatted-marker failure as the redirect failing. It is now the
  explicit `-d` refusal, which prints nothing.
- `tests/commit_memory.bats:180-186` names the wrong assertion as the mutation's
  red; the actual red line is the `!= *ahead*` negative.
- `tests/resolve_recovery.bats:390-400` describes a `gitlore_tier_paths`
  predicate the code deliberately lacks, contradicting `:474-480` in the same
  file.
- `tests/commit_memory.bats:444,456,481,505` say bats leaves `CLAUDECODE` unset.
  It inherits it, and the `unset` that follows is right.

**Test specificity and robustness**
- Non-final `[[ … ]]` assertions go silent under bash < 4.1. This is house style
  (574 baseline lines) and matters if macOS runs bats under `/bin/bash` 3.2.
- `tests/git_hook_pre_commit.bats:225`: the hook-entry off-pin case does not
  assert *why* it aborted.
- The non-fatal `|| agent_id=""` in `index-compose.sh` and `add-tier-batch.sh`
  is untested, and the fatal reads in the two sync hooks are not argued.
- `tests/git_hook_pre_commit.bats:388-392`: a failable `rev-parse` sits between
  `chmod a-w` and `run`.

**Design record**
- `git-hooks.md:50-57`: the `pre-commit` step list is out of execution order and
  omits the tier sync.
- The changelog entry's sequence omits the tier sync as well.
- "Sixth untracked `gitlore-…` file" undercounts; the same count is in the
  changelog and the `index-sync.sh` comment.
- `index-authoring-sync.md` does not record the atomic install, the `.tmp`
  exclusion and residual, merge-not-truncate, or the not-staged line.
  `configuration.md:42-44` still lists only two gitdir state files.
- Three alternatives argued at length are not named as rejected in
  `decisions.md`: composing a clean store, reporting a non-empty commit-path
  compose, and relaying instead of the subagent's own emission. D50's conclusion
  line also omits the dirty-only scope.
- `cc-platform.md:188`: "all four" is undefined outside `plans/`.
- `session.md` steps 6 and 10 disagree on the fast-forward failure exit.
- `merge-state-recovery.md:80-84` frames adoption as following a checkout only.
- The hub's Claude Code hooks bullet omits per-agent keying and the relay.
- D51's link points to an unheaded paragraph under D38, with no locator.
- `CLAUDE.md:61` cites a `plans/` file.

**Runbook drift** (baseline, not deliverable)
- Item 3.1 slice 4 still lists a case retired in slice 5.
- Item 1.2's fixed agent remedy sentence was superseded by "Follow the remedy on
  each line above" with no amendment.

## Gap Analysis

| Design requirement | Status | Reference |
|---|---|---|
| A — compose `additionalContext` states carrier re-texting | covered (pre-range, `c0963f5`) | outline §A |
| FR-B — the commit path composes before committing, dirty-only, rc-1 reports, rc-2 aborts | covered | Item 1.1; `resolve.sh` `gitlore_sync_memory_to_live` |
| FR-F — a tier off its pin aborts the commit | covered, with a regression | Items 1.2, 1.3; C1, M4 |
| FR-F — a recovered merge is adopted | covered | Item 1.3; `gitlore_adopt_recovered_merge`; Minor |
| FR-C — pre-image and compose stamp keyed per `agent_id` | covered | Item 2.1; all four consumers |
| FR-D — a keyed run stages its report; an unkeyed run folds it in | covered, incorrect under parallel hooks | Item 3.1; C2, M1, M6 |
| FR-D — reaches the parent *session* | partial | M2 (drain gated on an index change), M3 (session keying) |
| FR-D — SessionStart drains a marker that outlived its session | covered | Item 3.1 slice 3; `session.md` step 10 |
| FR-D — relay write is atomic (`8523b47`) | covered in code, unrecorded in docs | Minor (design record) |
| FR-E — D50 and D51 recorded: node, decisions index, hub, changelog | covered | M5 (D50 invariant), Minor |
| Node split (`951b83a`) — no dangling references | covered | prose partition, "checks that passed" |
| Out of scope: finding 2, a dirty-carrier query surface, description backfill | not delivered, correctly | outline §Out of scope |

## Summary

**Critical 2 · Major 7 · Minor 26** (two of the Minor are runbook drift)

Both Critical findings were reproduced in Layer 2. C1 is a regression Item 1.2
introduced into the transparent commit retry. C2 is a false premise (sequential
same-event hooks) under the whole relay write and drain design. M1–M3 and M6 are
the rest of FR-D's concurrency and delivery-timing surface. M4 and M5 concern
adopting a tier ahead of its pin. M7 is the gate paragraph in `CLAUDE.md`.
