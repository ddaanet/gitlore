# Runbook Review: tier-arrival-review-minors

**Artifact**: plans/tier-arrival-review-minors/runbook.md **Design**:
plans/tier-arrival-review-minors/outline.md (requirements M1–M21 in
classification.md) **Date**: 2026-09-15T15:30:32Z **Mode**: review + fix-all

## Summary

Every M1–M21 finding maps to an item, and the phase order matches the outline's
dependencies. I checked the anchors against the tree. Most file:line citations,
test names and function names are correct. Five slices could not have run as
written:
- the `mktemp` failure injection;
- the checkout-follow stub;
- the rule 2 fixture;
- the `:391` mutant;
- the `tiered-memory.md` count.

Several other slices duplicated existing tests. All of these are fixed in place.
One overage is flagged rather than fixed.

**Overall Assessment**: Ready

## Requirements Coverage

| Requirement | Phase | Items | Coverage | Notes |
|---|---|---|---|---|
| M1 unrepairable arm | 1 | 1.1/1 | Complete | 7th arg, other lines, two-fix remedy |
| M2 transient arms | 1 | 1.1/2, 1.1/4, 1.2/2 | Complete | commit build, checkout follow, mktemp tested; other arms share the helper |
| M3 walk-back wording | 1 | 1.1/3, 1.1/4 | Complete | |
| M4 push failure wording | 2 | 2.2 | Complete | |
| M5 mid-push race | 2 | 2.1/1 | Complete | reproduction-gated |
| M6 terminators | 3 | 3.1 | Complete | case 3 named as existing :1334 |
| M7 scratch dir | 1 | 1.2 | Complete | |
| M8 comment verb | 3 | 3.1 rider | Complete | |
| M9 `(K3)` | 5 | 5.1 | Complete | |
| M10 suffix decoy | 5 | 5.1 | Complete | |
| M11 unrepairable test | 5 | 5.2 | Complete | |
| M12 S1 split | 5 | 5.3 | Complete | |
| M13 rule paths | 5 | 5.3, 5.4 | Complete | rule 2 already covered by commit_memory.bats:717 |
| M14 merger rule 1 | 6 | 6.1 | Complete | |
| M15 pre-landing exits | 4, 6 | 4.1, 6.1, 6.2 | Complete | resolve skill :68 arm added |
| M16 git-hooks.md | 7 | 7.1 | Complete | |
| M17 tier-arrival-repair.md | 7 | 7.2 | Complete | |
| M18 tier-stores.md | 7 | 7.3 | Complete | |
| M19 node count | 7 | 7.4 | Complete | corrected target |
| M20 changelog | 7 | 7.7 | Complete | entry file needs no edit |
| M21 commit-gate.md | 7 | 7.5 | Complete | |

## Review Findings

### Specific checks requested

- **`commit_memory.bats:236` and rule 2.** It does not exercise rule 2. `:236`
  is a rule 1 carrier defect in a clean tier. The prefixless advisory sibling is
  rule 3 at `:308`. Rule 2 through the advisory arm is already tested at `:717`
  (`a manifest refusal is reported and does not abort the commit`). That test
  runs with root and carrier dirty, and asserts the commit lands and the
  `phantom` line is printed. See Major 3.
- **`git_hook_pre_commit.bats:391`.** It already asserts the restamp (`:425`).
  It has no tier `live`; `commit_memory.bats:148` has one. The runbook's mutant
  ("the arm treats a dirty carrier as advisory") is already killed by `:421`
  (`!= "the commit went ahead"`), so it proves no tightening. The outline's
  masking argument does not hold for this test. See Major 4.
- **Two tiers in `push_behind_vs_diverged.bats`.** They can coexist.
  `make_tier_remote` and `make_tier_in_memory` build a separate
  `$TMP_REPO/.bare-<tier>.git` per name. `mount_tier_at_live` takes a tier
  argument. `gitlore_tier_paths` reads `.gitmodules` in file order, so mount
  order sets loop order. `install_tier_live_snapshot_hook` hardcodes
  `.bare-ddaanet.git`, but the race tests do not need it.
- **The post-receive fixture is deterministic.** `post-receive` runs inside
  receive-pack before `git push` returns, so the remote's `live` has moved
  before the next tier's take fetches it. I traced both variants through the
  current `gitlore_push_stores`:
  - **behind:** `bb` is refused as behind. Its take pass fetches `aa`, repairs
    it to R and records R. The retry push checks only `bb`.
  - **ahead-of-HEAD:** `bb`'s `live`-ahead take does the same.

  In both variants memory's push records R, which `aa`'s remote lacks. Two
  conditions make this hold, and both are now in the runbook. D must be a child
  of the pushed commit, so the take fast-forwards rather than diverges. The hook
  must be one-shot, or the pass's push re-runs `update-ref` and rewinds `live`.
  Traced by reading, not run.

### Critical Issues

None.

### Major Issues

1. **Item 1.2/2: a nonexistent `TMPDIR` cannot reach the `mktemp` arm.**
   - Location: Item 1.2 slice 2.
   - Problem: `gitlore_git` (`util.sh:342`) runs `mktemp "${TMPDIR:-/tmp}/…"` on
     every call. The take's fast-forward (`lib/resolve.sh:1686`) uses it before
     the repair, so that step fails first and the repair never runs.
   - Fix: a `mktemp` stub that fails only when an argument contains
     `gitlore-repair.`. The stub rule in Run constraints now covers tools other
     than `git`.
   - **Status**: FIXED
2. **Item 1.1/4: the checkout stub breaks the take before the repair.**
   - Location: Item 1.1 slice 4.
   - Problem: `gitlore_merge_one_store` runs `checkout -q --detach live` at
     `:1693` before the repair's own call at `:1944`. A stub failing every such
     call fails the fast-forward instead.
   - Fix: the stub fails the second matching call. Run constraints gained a
     counter-file rule. Added an assertion that `HEAD` is back on the pin.
   - **Status**: FIXED
3. **Item 5.3: the rule 2 test cites the wrong fixture and duplicates `:717`.**
   - Location: Item 5.3, rule 2 advisory bullet.
   - Problem: `:236` is a rule 1 fixture, and `:717` already covers rule 2 on
     the advisory arm.
   - Fix: no test is added. `:717` is named as the coverage, and the executor
     proves it against the same mutant.
   - **Status**: FIXED
4. **Item 5.3: the `:391` mutant proves nothing.**
   - Problem: the named mutant already fails `:421` today.
   - Fix: two mutants that only the tightened test catches:
     - `return 1` becomes `return 2` in the abort arm. The executor first
       confirms it passes the untightened test.
     - The abort arm calls `gitlore_sync_tiers_to_live` before returning. That
       function advances a tier's `live` only when one exists
       (`lib/resolve.sh:929`), which is what the pin adds.

     Spelled the pin as `git -C memory/ddaanet branch -f live`.
   - **Status**: FIXED
5. **Item 7.4 would have edited a correct file.**
   - Problem: the subsystem has five nodes, and `index-composition.md:4-5`
     already says so. `tiered-memory.md:5` ("four sibling nodes") and `:23`
     ("four siblings") are correct. Only `index-authoring-sync.md:5` ("one of
     the four nodes") is wrong. "State that count in both files" would have made
     one of the two wrong. The planned `rg` pattern also missed "four siblings".
   - Fix: edit only `index-authoring-sync.md:5`, keep the others, and correct
     the `rg` pattern.
   - **Status**: FIXED
6. **Item 6.2: a build or commit refusal loops forever in the resolve skill.**
   - Location: `skills/resolve/SKILL.md:68`.
   - Problem: the skill handles only the merged-index line. For any other
     sub-agent report it goes to **Loop**. `resolve.sh` re-emits the directive,
     a fresh merger is approved, and the continuation is refused again. Editing
     only Summarize, which comes after Loop, never breaks the cycle.
   - Fix: added a `:68` arm. On the build or refused-commit line, send no
     `rejected:`, skip Loop, and go to Summarize. This follows from the
     outline's "no rejection cycle".
   - **Status**: FIXED
7. **Item 2.1: race slices were split so the reproduction gate could not act.**
   - Problem: slice 2 was marked "Guard if slice 1's green covers it; the red is
     against the pre-job code", which contradicts itself. The outline requires
     each variant to be red on its own, and a stop if neither reproduces.
   - Fix: one slice now holds both variant tests with the stop rule. The fixture
     is spelled out: P is recorded as the pin, D is a pre-pushed child of P
     carrying a duplicate pair, and the hook is one-shot `update-ref`. The
     former slice 3 (existing tests pass) became an item note.
   - **Status**: FIXED

### Minor Issues

1. **Item 1.1: the interface could not carry both remedy and `live_holds`.**
   - Problem: the checkout-follow arm needs `Run /gitlore:merge again.` and
     `the repair`. `report_refusal_and_walk_back` took only `live_holds`, so two
     executors would diverge.
   - Fix: `[<remedy>] [<live_holds>]`, in `walk_back_tier`'s order, with an
     empty remedy keeping the default. Transient arms call that helper.
   - **Status**: FIXED
2. **Item 1.1/1: `:744` needed no rewrite.**
   - Problem: `:771` still holds after the change, since there are no other
     lines, the remedy is unchanged and `live` still holds what arrived. The
     outline's "rewrite :771" is a no-op.
   - Fix: the runbook states that `:744` is not edited.
   - **Status**: FIXED
3. **Item 1.2/1: `TMPDIR` was unpinned.**
   - Problem: "exactly one line under `$TMPDIR`" depended on the ambient
     `TMPDIR`.
   - Fix: set to a fresh `$BATS_TEST_TMPDIR/tmp`, and dropped the now-unused
     `rev-parse --absolute-git-dir` lookup.
   - **Status**: FIXED
4. **Item 2.1: the pass's interim wording was unstated.**
   - Problem: 2.2/1 is red only if 2.1 reports with "not because of divergence".
   - Fix: 2.1 now says so. It also names the stale comments at `:1366-1367` and
     `:1395-1398`.
   - **Status**: FIXED
5. **Item 2.2: callers were inconsistent.** The target list omitted the inner
   `*)` arm that the text had it call. Fix: added it. The 2.2/1 stub now matches
   the call ending `aa push -q origin live`, and 2.2/2 names its fixture.
   **Status**: FIXED
6. **Item 3.1/3 duplicated `index_compose.bats:1334`.** That test already
   asserts byte equality for an unterminated file whose last line survives. Fix:
   named it instead of adding a test. 3.1/1 now uses the suite's `cmp -s` idiom
   rather than `od -c`. **Status**: FIXED
7. **Item 4.1/1 duplicated `resolve_compose.bats:394`.**
   - Problem: `:394` already refuses the commit (via `commit-msg`), sets
     `TMPDIR`, and asserts the kept `MERGE_HEAD` and the absent message file.
     The `:213` fixture cited for the new test refuses on its first run.
   - Fix: tighten `:394` to `-eq 1` plus the new line after git's reason. 4.1/2
     now uses `prepare_tier_merge_with_new_lines` and a stub matching
     `log --format=%s HEAD..`.
   - **Status**: FIXED
8. **Item 5.2: the first mutant was already killed.** An unstripped `live:` line
   fails `:768`. Fix: the mutant is now "the unrepairable arm prints every
   refusal line under the header, the carrier's included". Phase 5 now places a
   new assertion ahead of any existing one its mutant trips, and reports the
   line bats names. **Status**: FIXED
9. **Item 5.1: the decoy was out of step with the fixture.** Fix: the decoy is
   now `nested/my mem.d/MEMORY.md: …`, so the existing exact-output root query
   at `:1121` rejects the `grep -F` mutant. **Status**: FIXED
10. **Items 5.3 and 5.4: fixtures were underspecified.**
    - The root-weld hook test now names its fixture sources, `:191` and
      `:401-412`.
    - The rule 4 tests give their stray-line inputs and exact problem-line
      substrings.

    **Status**: FIXED
11. **Item 7.5 dropped information.** The replacement lost "is retried the same
    way". Fix: restored. Anchor corrected to `:57-60`. **Status**: FIXED
12. **Item 7.7 had nothing to change in the entry file.** The 2026-09-15 entry
    file already reads "any reason but divergence" (`:55`). Fix: marked "not
    edited", and the new entry is dated the day it is written. **Status**: FIXED
13. **Run constraints.**
    - The stub anchor `:410-425` becomes `:415-427`.
    - "Run `just precommit`" read as an executor step, which
      dispatch-constraints forbids. It now says the orchestrator runs it.

    **Status**: FIXED
14. **The runbook is over the 400-line soft cap.** It was 418 lines and is now
    473, before `just format-docs` reflow.
    - **Status**: UNFIXABLE: the runbook format is a single file that
      `/orchestrate` reads whole. A split is a structural call for my human
      partner, and a bounded overage on one cohesive plan is acceptable.

## Fixes Applied

- Run constraints: the orchestrator owns precommit; the stub rule is generalized
  to any tool, with a counter-file rule; anchor `:415-427`.
- Item 1.1: transient arms call `report_refusal_and_walk_back` with a remedy.
  The interface gains `[<remedy>] [<live_holds>]`. `:744` is not edited. 1.1/2
  names the problem-line substring. 1.1/4 fails the second checkout and asserts
  `HEAD` on the pin.
- Item 1.2: drops the gitdir lookup; pins `TMPDIR` in slice 1; uses a `mktemp`
  stub in slice 2.
- Item 2.1: pass placement reason, interim wording, stale comments, one
  reproduction slice with both variants and the stop rule, fixture detail, and
  the existing-tests note.
- Item 2.2: adds the inner `*)` caller, the counter-matched stub and the slice 2
  fixture.
- Item 3.1: `cmp -s`; slice 3 replaced by naming `:1334`.
- Item 4.1: slice 1 tightens `:394`; slice 2 gets its fixture and a precise
  stub.
- Phase 5 preamble: assertion placement and reporting the failing line.
- Items 5.1–5.4: decoy spelling, new mutants for 5.2 and `:391`, the root weld
  fixture, rule 4 inputs, rule 2 named as `:717`, and 5.4 input and assertions.
- Item 6.2: `:68` arm for build and commit refusals.
- Items 7.4, 7.5, 7.7: correct target file and pattern, restored clause, entry
  file left unedited.

## Design Alignment

- **Checked against the outline.** All four phase 1 function names and their
  current arities (6, 5, 5) match `lib/resolve.sh:1865-2020`. The `:1341` loop
  condition and the `:1368`/`:1394` take sites match. So do
  `gitlore_repair_index`'s termination logic (`index-compose.sh:432-448`) and
  the `:268-270` comment. `scripts/resolve.sh:105-109` and `:309-316` match.
  `agents/memory-merger.md:28, 37-39` and `skills/resolve/SKILL.md:82-87` match.
  So does every docs anchor except `commit-gate.md` (`:57-60`) and the changelog
  entry file, both corrected above.
- **Outline refinements, noted as such.**
  - The report helper takes both remedy and `live_holds`.
  - The pass runs before the memory-remote check. The outline says "before
    memory's fetch and push"; this placement is compatible and keeps the "every
    mounted tier was published" line true.
  - Existing tests are tightened instead of duplicated at `resolve_compose:394`,
    `index_compose:1334` and `commit_memory:717`.
  - The resolve skill gains a `:68` arm.
- **Scope.** None of the tracked exclusions is pulled in. The 400-line script
  cap on `lib/resolve.sh` (2182 lines) is out of scope per the outline. Test
  files grow by roughly 150–250 lines in total across three already-large
  suites. No phase needs a split.
