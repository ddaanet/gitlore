# Phase 5 checkpoint review — test specificity

Scope: net diff `67cdd2f..HEAD` over `tests/index_compose.bats`,
`tests/merge_memory.bats`, `tests/git_hook_pre_commit.bats`,
`tests/commit_memory.bats` and `tests/resolve_compose.bats`, against M9–M13.

## Findings closed

- **M9** — `(K3)` is gone from the `gitlore_repair_index` section header.
- **M10** — the suffix decoy `nested/my mem.d/MEMORY.md: …` is in the
  attribution fixture. The exact-output assertion on the `my mem.d/MEMORY.md`
  query excludes it.
- **M11** — the net `merge_memory.bats` diff sits entirely in
  `"an arrival the repair cannot fix walks back and names upstream"`: memory
  `HEAD` is pinned across the take, and no `gitlore:   …ddaanet/MEMORY.md: `
  stderr line is allowed. The `:1002` test
  (`… beside a root duplicate reports both and the two-fix remedy`) has no hunk
  in `git diff 67cdd2f..HEAD`, so it reads as it did before Phase 5.
- **M12** — the root weld now aborts through `scripts/git-hooks/pre-commit`,
  with status 1, the weld line, `aborted`, no `the commit went ahead`, `HEAD`
  unmoved and the restamp. The carrier hook test gains the `live` pin, a
  `live`-unmoved assertion and `-eq 1`.
- **M13** — rule 4 on the dirty-carrier abort is a new test in
  `commit_memory.bats`. Rule 2 on the advisory arm is proved against the
  existing manifest-refusal test (per the runbook, no new test). Rule 4 on the
  merged-root gate is a new test in `resolve_compose.bats`.

## Mutant evidence

Every report quotes a `not ok` for each named mutant. I re-ran these in place,
using a backup under `.git/`, then restored the file; `git status -- scripts/`
was empty afterwards:

- The rule-4 skip in `gitlore_compose_check_index` (`elif false && …`):
  - `resolve_compose.bats`: `not ok … keeps the merge unlanded`, line 597,
    `[[ "$stderr" == *"memory/MEMORY.md: interleaved non-bullet line"* ]]`. This
    matches the Item 5.4 report.
  - `commit_memory.bats`: `not ok … aborts the memory commit`, line 218,
    `[ "$status" -eq 1 ]`. This matches the Item 5.3 report.
- The unanchored `grep -F` in `gitlore_compose_problems_in`:
  `not ok 1 problem attribution matches the exact file prefix`, line 1123. This
  matches the Item 5.1 report.

The new negative assertions:

- `run ! grep -Eq '^gitlore:   .*ddaanet/MEMORY\.md: '` in `merge_memory.bats`
  is shown failing in Item 5.2 under mutant 1. That mutant makes the carrier
  line appear.
- `!= *"the commit went ahead"*` in the new hook test is proven in the
  orchestrator addendum to Item 5.3.

No new negative assertion lacks proof.

## Item 5.4 fixture deviation

The claim holds against `scripts/lib/index-merge.sh`:

- `_gitlore_index_merge_bullets` rebuilds the bullet block only from the paths
  `gitlore_order_merge` yields.
- `gitlore_index_merge_paths` skips any line `gitlore_bullet_path` rejects, so a
  non-bullet line inside the block has no path and is not emitted. The merge
  still returns 0.
- A side whose paths contain a duplicate (`sort | uniq -d`) makes
  `gitlore_index_merge` return 2, and `gitlore_merge_indexes` then leaves git's
  line-wise result in place (`[ "$rc" -ge 2 ] && continue`).

The test is specific to the interleaved line. The duplicate alone would produce
status 1 and `was not committed`, but the test also asserts
`memory/MEMORY.md: interleaved non-bullet line`. The rule-4 mutant fails on
exactly that line while status stays 1.

**Fixed:** the comment called the duplicate "load-bearing, not incidental" and
said the merge "drops any line that carries no path", which reads as design. It
now says the line is lost without a report, calls that a gap of its own outside
this test's coverage, and describes the duplicate as the way the stray line
reaches the check. It is in the present tense and cites nothing.

## Comment and naming fixes

- `tests/commit_memory.bats` (new rule-4 test): the comment cited "The :140
  fixture", which is a line number. It now reads "The duplicate-carrier fixture
  above, … a rule 4 problem aborts as rule 1 does."
- `tests/index_compose.bats`
  (`problem attribution matches the exact file prefix`): the fixture comment
  listed only the space and prefix-tier traps. It now names the third trap the
  new decoy adds: a longer path ending in the queried one, which an unanchored
  match would take.

No other test comment cites `plans/`, `memory/`, runbook or slice ids, or line
numbers. "rule N" and "rc-1 arm" are existing suite vocabulary.

## Verification after the fixes

The fixes change comments only.

- `shellcheck -x` passes on the three edited files.
- The three affected tests each pass: `… keeps the merge unlanded`,
  `an interleaved non-bullet line in a dirty carrier …` and
  `problem attribution matches the exact file prefix`.
- `git status -- scripts/` is empty.

Nothing is unfixable.
