# Deliverable Review: index-edit-propagation

**Date:** 2026-09-14 **Methodology:** docs/design.md §6.8 "Deliverable review"

Fresh review of the deliverables as they stand after the fix pass (`7485483`,
`081e364`, `e36e7fc`, `38de36b`, `45624bd`, `7d20aab`). The 2026-09-12 review
this file replaces is in git at `ce0fdd2`.

Baseline: `outline.md` §B–D and §Design record, as amended by `runbook.md` ("as
executed" / "as amended" notes take precedence), with `relay-redesign.md`
superseding the relay design (D51 revised). Range `b6dbe92..HEAD`, excluding the
unrelated commits `3d50a1f`, `c2e7950`, `ae54c1b` and `a0b416b`. `CLAUDE.md` is
out of scope: its gate paragraph, and the prior review's M7, are an open
decision in the task frame.

Layer 1 ran (deliverables > 2000 lines) as three opus partitions:
`deliverable-review-code.md`, `deliverable-review-test.md`,
`deliverable-review-prose.md`. Layer 2 ran in the main session: the
cross-cutting checks, and a check of each partition's Major against its source.

**Probe debris.** The code partition's first relay probe ran against a plain
`git init` store, which by code m1 below wrote 122 inert
`gitlore-relay-S1-a{0,1,2}-*` files into this repository's own `.git/`. Their
removal was refused by the auto-mode classifier in both the subagent and the
main session. They are inert: nothing drains the parent gitdir and no real
session id is `S1`.

```sh
G=/Users/david/code/gitlore/.git
find "$G" -maxdepth 1 -type f -name 'gitlore-relay-S1-a[012]-*' -delete
ls "$G" | grep -c '^gitlore-relay-'   # prints 0 when they are gone
```

## Inventory

| Type | File | + / − (range) |
|---|---|---|
| Code | `scripts/lib/resolve.sh` | 312 / 14 |
| Code | `scripts/lib/index-sync.sh` | 217 / 4 |
| Code | `scripts/lib/index-compose.sh` | 29 / 3 |
| Code | `scripts/lib/util.sh` | 9 / 0 |
| Code | `scripts/resolve.sh` | 66 / 5 |
| Code | `scripts/cc-hooks/relay-drain.sh` (new) | 52 / 0 |
| Code | `scripts/cc-hooks/index-sync-post.sh` | 55 / 3 |
| Code | `scripts/cc-hooks/session-start.sh` | 50 / 0 |
| Code | `scripts/cc-hooks/index-compose.sh` | 45 / 3 |
| Code | `scripts/cc-hooks/index-sync-pre.sh` | 25 / 5 |
| Code | `scripts/cc-hooks/add-tier-batch.sh` | 17 / 3 |
| Configuration | `hooks/hooks.json` | 8 / 0 |
| Test | `tests/index_sync.bats` | 708 / 1 |
| Test | `tests/commit_memory.bats` | 505 / 0 |
| Test | `tests/cc_hook_index_compose.bats` | 355 / 5 |
| Test | `tests/resolve_recovery.bats` (new) | 343 / 0 |
| Test | `tests/git_hook_pre_commit.bats` | 187 / 0 |
| Test | `tests/cc_hook_session_start.bats` | 166 / 0 |
| Test | `tests/index_compose.bats` | 165 / 4 |
| Test | `tests/resolve_compose.bats` (new) | 94 / 0 |
| Test | `tests/cc_hook_add_tier.bats` | 64 / 2 |
| Test | `merge_memory`, `plugin_distribution`, `push_memory`, `tier_lockstep` | 64 / 2 |
| Test | `tests/helpers/{fixtures,setup,tier-fixtures}.bash` | 65 / 0 |
| Human docs | `docs/references/git-hooks.md` (new, split) | 228 / 0 |
| Human docs | `docs/references/memory-entry-points.md` (renamed) | 13 / 116 |
| Human docs | `index-authoring-sync.md`, `cc-platform.md`, `tier-stores.md`, `index-composition.md`, `session.md`, `merge-state-recovery.md`, `configuration.md`, `commit-gate.md` | 290 / 83 |
| Human docs | `docs/decisions.md`, `docs/design.md` | D50, D51 and hub hunks |
| Human docs | `docs/changelog.md` and six 2026-09-11 / 2026-09-13 entries | 286 / 0 |

Conformance summary: every item, slice and relay-redesign case is delivered, and
every prior Critical and Major is resolved at HEAD (§Prior findings). The new
defects sit in the fix pass itself. The take walk-back that resolves M5 can
wedge publishing on a defect it misattributes, and the continuation's new `||`
call masks a staging failure. Two relay tests cannot see the regressions they
exist for, and one proof sentence in the hooks node cites renumbered steps.

## Prior findings

| Prior | Status at HEAD | Evidence |
|---|---|---|
| C1 pin guard refuses a half-landed retry | resolved | landing record; `commit_memory.bats:296` red on pre-fix scripts; code probe of a `live.lock` variant retries to exit 0 |
| C2 relay races under parallel hooks | resolved | write-once names; 40 writers × 30 drains probe clean ×3; `index_sync.bats:972` red on a race mutation |
| M1 drain unlinks an unread report | resolved | drain removes only listed names, `.tmp` excluded |
| M2 drain gated on an index change | resolved | `relay-drain.sh` runs on every main-thread batch |
| M3 markers keyed by agent only | resolved | names carry the session; both drains scope to it |
| M4 "stage the gitlink by hand" | resolved | remedy adopts into root first; wording gap in Minor |
| M5 take and continuation stage after a failed up projection | resolved | both record nothing; walk-back introduces Major 1 |
| M6 no concurrent test | resolved | library case races; hook case only launches concurrently (Minor) |
| M7 `CLAUDE.md` gate paragraph | out of scope | open decision |
| Minors, 26 | 22 resolved, 4 partly | partitions' status sections |

## Critical Findings

None.

## Major Findings

### 1. A carrier defect arriving with a take is misattributed, and wedges every push

- **Where:** `scripts/lib/resolve.sh:1778-1787` (`gitlore_adopt_tier_into_root`
  walk-back) and `scripts/resolve.sh:179-200` (`rest_unadopted_tier`), reached
  from `gitlore_push_stores` and so from `scripts/git-hooks/pre-push`.
- **Requirement:** D50, and remedies that can be carried out.
- **Mechanism:** `gitlore_compose_up` refuses through `gitlore_compose_check`,
  which validates the arriving carrier too (duplicate pointer, stray line,
  welded line). The walk-back checks the tier out at the pre-take commit, which
  does not hold the defect, then names `memory/<tier>/MEMORY.md` and says "Fix
  the store, then run /gitlore:merge again". That file is clean in the worktree.
  Every later take refuses and walks back again, and `gitlore_push_stores` takes
  whenever `live` is ahead, so every `/gitlore:push` and parent `git push`
  fails. Fixing it by hand means committing on top of `live`, which the pin
  guard then refuses, and no remedy describes that route.
- **Reproduced** (code partition, real `merge-memory.sh` and `push-memory.sh`,
  tier remote carrying a duplicated pointer): take exits 1 naming the carrier;
  tier `HEAD` equals the pin, `live` is ahead; the named file has no duplicate;
  `push-memory.sh` exits 1 with the same lines.
- **Impact:** one malformed commit published to a shared tier by another
  consumer stops this repository's memory publishing and parent pushes. A welded
  line is what appending to a carrier with no trailing newline produces.

### 2. `|| tier_unadopted=1` suspends errexit across `compose_merged_indexes`

- **Where:** `scripts/resolve.sh:247`, with the function's final
  `gitlore_git -C "$memroot" add -- MEMORY.md` at `:152`.
- **Requirement:** D50 on the continuation; failures observable as what they
  are.
- **Mechanism:** in an `||` list the whole function runs without errexit and
  returns its last command's status. A memory `index.lock` outlasting
  `gitlore_git`'s retries on that final `add` sets `tier_unadopted=1` for a tier
  that was adopted. The continuation commits the merge, skips the gitlink and
  bookkeeping, clears the merge state, and rests the tier on its old pin while
  root holds the up-projected block unstaged. It prints "Fix the store" and
  never names the lock. The earlier `add -A` failures are swallowed as well. For
  a memory merge the same path prints "tier '' stays on the merge commit". At
  `b6dbe92` the bare call aborted before the commit and kept the merge state for
  a retry.
- **Reproduced (mechanism)** by the code partition: the extracted function under
  `set -euo pipefail`, with the final `add` stubbed to fail, yields
  `tier_unadopted=1` and continues. Confirmed from source in Layer 2.
- **Impact:** root describes merged facts against a tier on its pre-merge pin;
  the next compose-down projects them onto the old carrier as dangling lines,
  which dirties the tier and blocks the retake the remedy asks for. Narrow
  trigger: a lock held past the retry schedule.

### 3. "An unkeyed run leaves a marker in place" cannot see a returning drain

- **Where:** `tests/index_sync.bats:771`,
  `tests/cc_hook_index_compose.bats:294`.
- **Requirement:** relay-redesign slice 2 case 3; vacuity.
- **Mechanism:** both cases stage the marker under the empty session
  (`nosession`) and run the hook with `session_id: "test-session"`. A drain
  branch returning to either reporting hook would take the D51 shape,
  `gitlore_relay_drain "$mempath" "$session"`, and never touch a `nosession`
  marker. Confirmed from source in Layer 2.
- **Reproduced** (test partition): adding that drain to both hooks leaves both
  cases, the concurrency case and the session-isolation cases green; a control
  with the marker under `test-session` goes red. The regression is C2's drain
  half, every relayed report doubled, and no test catches it.

### 4. The drain side of "empty session maps to nosession" is untested

- **Where:** `tests/index_sync.bats:1126`; `scripts/lib/index-sync.sh:207`.
- **Requirement:** relay-redesign slice 1 case 6, "on both sides".
- **Reproduced** (test partition): making the drain sanitize `""` to an empty
  prefix leaves all 24 relay cases green. The case drains with the literal
  `nosession`, never `""`. Production payloads carry `session_id`, so the reach
  is small; the specified contract is still unpinned.

### 5. The gitlink invariant's proof sentence cites steps that no longer exist

- **Where:** `docs/references/git-hooks.md:81-82`.
- **Requirement:** usability, accuracy (broken reference).
- **Doc:** "`pre-commit` makes it `live` itself: step 5 stages the commit step 4
  just advanced `live` to." The list has four steps: 3 syncs memory and advances
  `live`, 4 stages the gitlink. The minor pass merged the old steps 3 and 4
  without updating this sentence, which is the one-line proof NFR5 and D46 rest
  on. Confirmed in Layer 2.

## Minor Findings

**Commit and merge paths (code)**

- The relay write resolves its path with `rev-parse --git-path`, the drain and
  sweep with `--absolute-git-dir`. For a store whose `.git` is a directory the
  write lands relative to the cwd and silently misses the drain. Unreachable
  from gitlore's own install, which absorbs gitdirs; reproduced by accident.
- The pin-guard abort says "the approved summary is still in place", but every
  remedy it prints writes into the store and invalidates the approval.
- The restamp comment claims the per-tier stale-merge guard fails only after
  preparing a merge; several arms prepare nothing, so an earlier tier's up
  projection can leave the approval stale. The restamp also blesses any
  concurrent write made before it.
- `push_or_report` exits inside the continuation before `rest_unadopted_tier`,
  leaving an unadopted tier on the merge commit with `live` not ahead, where
  `/gitlore:merge` finds nothing to adopt. The changelog names only two resting
  exceptions.
- The ahead-of-pin remedy does not say to replace root's existing `<tier>/`
  lines, so following it literally leaves duplicate or dangling pointers.

**Tests**

- The hook-level concurrency case launches both hooks at once but their write
  windows never overlap; a count-then-create name mutation stays green there and
  reds the library case.
- "A failure keeps the approval" is pinned on one arm; removing the tier-commit
  and memory-commit restamps and the landing record's parent check leaves every
  case green. No hook-level half-landed retry exists.
- The occupied-name refusal and the drain's `-type f` lost their cases in the
  redesign; deleting either stays green.
- The relay write's id sanitization is unpinned; splicing raw ids stays green.
- `cc_hook_session_start.bats:458` never asserts the unreadable marker was
  reached or removed, and its comment is stale.
- RED-phase narration ships: "RED stub" references to a stub that does not
  exist, "today's code" framing, a false `sync_feed` comment, and root skips
  kept after switching to an `mv` stub.
- `add-tier-batch.sh`'s `|| agent_id=""` fallback is still untested.
- No in-suite spaced-root case covers the fix-pass paths; a spaced `TMPDIR`
  probe passes, and the quoted `resolve.sh` remedies are asserted nowhere.
- Non-final `[[ ]]` assertions go silent under bash < 4.1 (house style).

**Design record (prose)**

- `git-hooks.md:162-168`: "every later failure restamps it" has two
  non-restamping returns (the tier guard loop, a non-divergence advance
  refusal). Same classification as the code comment above.
- "The only consumer / reader" of relay reports, in `index-authoring-sync.md`,
  the hub, the changelog entry and two hook comments, omits `SessionStart`'s
  drain. D51's line says the precise "only PostToolBatch consumer".
- D50's adoption invariant is stated more broadly than the code:
  `git-hooks.md:192-194` omits the rests that do not walk back, and
  `merge-state-recovery.md:84-85` ("the one shape", cited as D43) contradicts
  the landed-tier exception in `git-hooks.md`; a "therefore" lost its reason.
- `tier-stores.md:171-172` and its changelog entry say the unadopted
  continuation publishes; every `/gitlore:merge`-prepared merge is no-publish.
- Named rejected alternatives with no entry in their node's Rejected section:
  composing a clean store, reporting a non-empty commit-path compose, relaying
  in place of the subagent's emission. Staging nothing without the walk-back is
  argued but not named in `decisions.md`.
- `index-authoring-sync.md:113`: "a report shares the pre-image's key" is left
  from the per-agent design; the relay keys on session and agent.
- `index-composition.md:103-105` under-enumerates the pin rule's callers.
- `configuration.md:43-48` omits the keyed pre-image and stamp files, and says
  the drain folds into "the parent's own report", which `relay-drain.sh` lacks.
- The hub's Claude Code hooks bullet links neither `index-authoring-sync.md` nor
  `cc-platform.md`.
- `docs/changelog.md`: the four 2026-09-13 bullets are blank-line separated,
  which makes the whole list loose.

## Gap Analysis

| Design requirement | Status | Reference |
|---|---|---|
| FR-B — commit path composes, dirty-only, rc 1 reports, rc 2 aborts | covered | `gitlore_sync_memory_to_live`; commit-path order verified |
| FR-F — a tier off its pin aborts; a half-landed retry completes | covered | landing record; `commit_memory.bats:296`, `:325`, `:353` |
| FR-F — a recovered merge is adopted, with a short-circuit | covered | `gitlore_adopt_recovered_merge`; `resolve_recovery.bats:397` |
| D50 — compose up and stage the pair, or stage nothing | covered, with defects | take and continuation; Majors 1, 2 |
| FR-C — pre-image and stamp keyed per `agent_id` | covered | four consumers; fallback cases (one hook unpinned) |
| FR-D / D51 — write-once, session+agent keyed, one PostToolBatch drainer | covered | `relay-drain.sh`, `hooks.json`, `plugin_distribution.bats:202` |
| D51 — SessionStart own-session drain and 7-day sweep | covered | `cc_hook_session_start.bats:366`, `:401` |
| relay-redesign slices 1–2 named cases | covered, two weak | Majors 3, 4 |
| relay-redesign §Docs | covered | every item landed; prose Minors |
| Design record — D50, D51 in node, decisions index, hub, changelog | covered | Major 5, prose Minors |
| Out of scope: finding 2, dirty-carrier query, description backfill | not delivered, correctly | outline §Out of scope |

Cross-cutting checks that passed (Layer 2): `relay-drain.sh` is registered as
its own `PostToolBatch` group, executable and covered by the distribution suite;
every relay call site passes `mempath session agent tag sysmsg ctx` in the
library's order; `agent_id` (never `agent_type`) keys every consumer;
`add-tier-batch.sh` drops the keyed stamp and argues its parallel ordering; the
hub, `cc-platform.md`, `session.md`, `configuration.md` and `decisions.md` name
the relay consistently apart from the "only consumer" Minor; the docs link
checker exits 0 and every changed doc is under 400 lines.

## Summary

**Critical 0 · Major 5 · Minor 24**

All prior Critical and Major findings are resolved at HEAD. Majors 1 and 2 are
new defects in the fix pass's D50 failure arms, one reproduced end to end and
one reproduced at the mechanism. Majors 3 and 4 are relay tests that stay green
under the regressions they are named for, both reproduced by mutation. Major 5
is a broken step reference in the hooks node.
