# Deliverable Review: unadoptable-tier-arrival

**Date:** 2026-09-15 **Methodology:** edify deliverable review (ISO 25010 / IEEE
1012 axes), two layers: three delegated opus reviews (code, test, prose) plus an
interactive cross-cutting pass. **Range:** `e60ff38..HEAD`, against
`plans/unadoptable-tier-arrival/outline.md`. Decisions recorded in the run
reports (message wording, the rest-guard remedy, the weld containment guard,
tier-before-memory gates, the D52 node, the push skill edits, S7 dropped) are
read as taken.

Layer 1 reports:
- `reports/deliverable-review-code.md`
- `reports/deliverable-review-test.md`
- `reports/deliverable-review-prose.md`

## Inventory

| Type | File | +/− |
|---|---|---|
| Code | `scripts/lib/index-compose.sh` | +203/−8 |
| Code | `scripts/lib/resolve.sh` | +265/−35 |
| Code | `scripts/resolve.sh` | +92/−34 |
| Code | `scripts/cc-hooks/memory-commit-batch.sh` | +4/−2 |
| Test | `tests/merge_memory.bats` | +422 |
| Test | `tests/resolve_compose.bats` | +349/−12 |
| Test | `tests/index_compose.bats` | +252 |
| Test | `tests/commit_memory.bats` | +183 |
| Test | `tests/push_behind_vs_diverged.bats` | +134 |
| Test | `tests/git_hook_pre_commit.bats` | +37 |
| Test | `tests/tier_divergence.bats` | +22 |
| Test | `tests/cc_hook_memory_commit_batch.bats` | +21 |
| Agentic prose | `agents/memory-merger.md` | +5/−3 |
| Agentic prose | `skills/merge/SKILL.md` | +11 |
| Agentic prose | `skills/push/SKILL.md` | +9/−4 |
| Agentic prose | `skills/resolve/SKILL.md` | +11/−4 |
| Human docs | `docs/references/tier-arrival-repair.md` (new) | +164 |
| Human docs | `docs/references/tier-stores.md` | +58/−24 |
| Human docs | `docs/references/git-hooks.md` | +46/−28 |
| Human docs | `docs/references/merge-and-resolve.md` | +20/−9 |
| Human docs | `docs/references/index-composition.md` | +16/−8 |
| Human docs | `docs/references/commit-gate.md` | +10/−4 |
| Human docs | `docs/references/tiered-memory.md` | +9/−4 |
| Human docs | `docs/design.md` | +19/−15 |
| Human docs | `docs/decisions.md` | +12/−4 |
| Human docs | `docs/changelog.md` + 2026-09-15 entry | +88 |

Every S1–S6 requirement has an implementation, and every S1–S4 postcondition
maps to a test that can fail. The code reviewer's probes are the basis for this:
- `gitlore_repair_index` under `set -euo pipefail`, with a spaced tier directory
  and seven defect shapes, produced output that passed the check.
- `gitlore_compose_problems_in` with glob characters, spaces and a tier name
  that prefixes another produced exact attributions.

`shellcheck -x` is clean, the docs link check is clean, and every doc is under
400 lines. Every message string the skills quote appears byte for byte in the
scripts.

## Critical Findings

None.

## Major Findings

1. **`skills/merge/SKILL.md:68-72`: the report tells the agent `/gitlore:push`
   publishes a repair that is resting on local problems** (actionability,
   accuracy).

   **What the skill says.** "Say that the repair is committed in the tier's
   local `live` and `/gitlore:push` publishes it" is unconditional, and the
   resting case follows it.

   **What the code does.**
   - In `gitlore_adopt_repair_arrival`, the `/gitlore:push publishes it` line
     prints only after the retry succeeds.
   - When the retry refuses on root, the take walks back.
   - A later push reaches `gitlore_live_ahead_of_head`, and its take refuses
     again, so the push fails.
   - `tier-arrival-repair.md` agrees: "A repair resting on local problems
     publishes nothing until they are fixed."

   **Impact:** the user is told a push will publish, and the push fails until
   they fix root.

   **Fix:** make the push claim conditional on the run printing that line. In
   the resting case, say the repair publishes once the listed problems are
   fixed.

## Minor Findings

**Error signaling and messages**
- **`scripts/lib/resolve.sh:1913-1942`: unrepairable arm.** It prints only the
  carrier's problems, because `$composed` never reaches
  `gitlore_adopt_repair_arrival`. Root, manifest and other-tier problems from
  the same refusal stay hidden until a later take.
- **Same function: read/build/lock arms.** They print no problem list and end
  with "Fix the store", although the next take simply repairs again.
- **`scripts/lib/resolve.sh:2018`: walk-back message.** It says "its local
  'live' keeps what arrived". In the resting-repair case `live` holds the
  repair, which `tier-stores.md:180-181` states correctly. The merge skill
  relays this line verbatim.
- **`scripts/lib/resolve.sh:1399-1407`: `behind` arm's retry push.** A failure
  is always reported as "not because of divergence", even when the cause is a
  race with origin advancing. It also duplicates the message block at 1432–1436.
- **Related race (interactive pass, unprobed).** A take run during one tier's
  push iteration can repair a different tier whose iteration already pushed.
  Memory's push then records a gitlink that tier's remote lacks. It needs origin
  to advance mid-push, and is otherwise safe (code review's K6 check).

**Byte preservation and robustness**
- **`scripts/lib/index-compose.sh:432-448`: newline loss (probed).** When the
  dropped duplicate is an unterminated last line, the surviving line before it
  loses its newline. That changes the bytes of a line no rule named.
- **`scripts/lib/resolve.sh:1906, 1933`: scratch directory.** A take killed
  between `mktemp -d` and `rm -rf` leaves `gitlore-repair.XXXXXX` in the tier
  gitdir. There is no trap, and one directory accumulates per killed take.

**Comments and naming**
- **`scripts/lib/index-compose.sh:268-270`: wrong verb.** "no take can walk back
  from" should read "no take can adopt past".
- **`tests/index_compose.bats:1143`: outline id in shipped code.** The section
  header cites `(K3)`.

**Test specificity and coverage**
- **`tests/index_compose.bats:1105-1127`: unanchored prefix.** No decoy has the
  queried path as a suffix of a longer path, so an unanchored `grep -F` passes.
  Probed: that mutant attributes `memory/org/memory/MEMORY.md:` to root. The
  shipped `case` is anchored.
- **`tests/merge_memory.bats:744-778`: worktree-carrier attribution.** Nothing
  rejects a worktree-carrier-prefixed problem line, and memory HEAD is not
  asserted unchanged.
- **Split postconditions.** S1's "aborts the same way" is split across entry
  points:
  - the root weld runs only through `commit-memory.sh`, with no restamp
    assertion;
  - the pre-commit carrier test has no `live` pin and asserts `-ne 0`.
- **Untested rule paths.** Nothing tests:
  - rule 4 on the K5 abort;
  - rule 2 on the K5 advisory arm;
  - rule 4 on the K4 merged-root gate.

  Each shares tested attribution.

**Prose accuracy and clarity**
- **`agents/memory-merger.md:28`: duplicate paths.** The structure rule never
  says no two bullets may share a path (rule 1). The gate catches it at the cost
  of a rejection cycle.
- **`agents/memory-merger.md:39` and `skills/resolve/SKILL.md:85-86`:
  "otherwise" branch.** It reads every other exit as post-landing. A failed
  message build or a refused merge commit also exits 1 with `MERGE_HEAD` kept.
- **`docs/references/git-hooks.md:155-157`: ambiguous clause.** It can be read
  as a root problem aborting regardless of dirtiness.
- **`docs/references/tier-arrival-repair.md:20-26`: tense.** The opening
  describes the unrepaired wedge in the present tense, as current behaviour.
- **`docs/references/tier-stores.md:190-195`: dangling "instead".** It has no
  referent.
- **`docs/references/index-authoring-sync.md:5`: node count.** It still says
  "one of the four nodes". There are five.
- **`docs/changelog.md:15-16`: dangling "other".** "Any other reason" has no
  antecedent in the index line.
- **`docs/references/commit-gate.md:57-61`: off-pin tier.** It lists an off-pin
  tier as fixed by an edit; its remedy is a checkout or a take.

Tracked items the reviewers met again are not counted: the rootless store, the
batch-retry approval gap, the untested restamp/mode/CRLF arms, the
never-published memory push, the bound on refuse/re-synthesize cycles, and the
400-line cap on the scripts.

## Gap Analysis

| Design requirement | Status | Reference |
|---|---|---|
| S1 attribution helper | Covered | `index-compose.sh` `gitlore_compose_problems_in`; `index_compose.bats:1105` |
| S1/K5 abort on dirty problem file, restamp; advisory otherwise | Covered | `lib/resolve.sh` rc 1 arm; `commit_memory.bats:140-322`, `git_hook_pre_commit.bats:391` |
| S2/K3 `gitlore_repair_index` rules, byte preservation | Covered (minor newline edge) | `index-compose.sh`; `index_compose.bats:1143-1369` |
| S2/K1 plain commit in the take, interruption-safe | Covered | `gitlore_adopt_repair_arrival`, `gitlore_adopt_commit_repair`; `merge_memory.bats:558-812` |
| S2/K2 attribution, resting, unrepairable, refused `live` | Covered | `merge_memory.bats:703, 744, 812` |
| S2 fetch-first; reach via adoption and fast-forward | Covered | `gitlore_merge_one_store`; `merge_memory.bats:780, 859-958` |
| K6 publication, both push arms | Covered | `gitlore_push_stores`; `push_behind_vs_diverged.bats:338, 376, 404` |
| S3/K4 continuation gate | Covered | `compose_merged_indexes`; `resolve_compose.bats:164-290, 415-452` |
| S4 `push_or_report` 0/1/2, rest guard, remedy | Covered | `scripts/resolve.sh`; `resolve_compose.bats:527-632` |
| S5 merger, resolve, merge skill prose | Covered (Major 1) | `agents/memory-merger.md`, `skills/*/SKILL.md` |
| S6 D52, D50 amendment, rejected alternatives, changelog | Covered | `tier-arrival-repair.md`, `decisions.md`, `git-hooks.md`, `design.md`, changelog |
| S7 memory fact | Dropped by decision | — |
| Unspecified: push skill relay; tier-before-memory gate order; stale-merge directive before summary | Justified (run reports) | `skills/push/SKILL.md`, `scripts/resolve.sh`, `lib/resolve.sh:997-1011` |

## Summary

| Severity | Count |
|---|---|
| Critical | 0 |
| Major | 1 |
| Minor | 21 |
