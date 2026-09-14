# Minor findings pass 2 — index-edit-propagation

Every edit below is in the working tree, uncommitted. No mutation is left in
place: each one was applied from a backup copy and restored, and `cmp` confirmed
the restore.

## Verification

The pass was interrupted before verification; a second agent verified it.

- `just lint` reported `cached (inputs unchanged)`: its gate was recorded after
  the file-level `# shellcheck disable=SC2030,SC2031` landed in
  `tests/commit_memory.bats` and `tests/merge_memory.bats`. A direct
  `scripts/lint-shell.sh` run confirmed it (138 files clean), so the disable is
  accepted and no lint finding needed fixing.
- Every bats file on both lists ran whole, one at a time, through
  `scripts/run-bats.sh`. None failed, so no repair was needed and nothing is
  recorded as pre-existing or unrelated.
- `just format-docs` ran after this report was written; the docs link checker
  exits 0.

## code m1 — relay write vs drain gitdir form: fixed

- `scripts/lib/index-sync.sh`: `gitlore_relay_write` now builds the marker from
  `rev-parse --absolute-git-dir`, with a comment.
- New case in `tests/index_sync.bats`:
  `relay_write lands where the drain looks for a store whose .git is a directory`.
- Red before the fix, on the `GITLORE_RELAY_SYSMSG == *PLAIN-BODY*` assertion.
  Green after.

## code m2 — pin-guard abort promises the approval survives: fixed

- `scripts/lib/resolve.sh`: the agent arm now reads "Every remedy writes into
  the memory store, so the summary has to be approved again before the retry."
- `tests/commit_memory.bats`, case
  `the pin-abort's ahead wording reaches both…`: added `!= *still in place*` and
  `== *approved again*`.
- Red before the fix on `!= *still in place*`. Green after.

## code m3 — restamp coverage: part fixed, part recorded

- **Fixed, non-divergence tier `live` advance refusal.** The arm in
  `gitlore_sync_tiers_to_live` (HEAD and `live` agree, or not diverged) returned
  without `touch`. It now restamps; the yield arm is restructured to return
  first.
  - New case:
    `a tier live advance refused without divergence keeps the approval for the retry`.
    It stands in `gitlore_classify_refusal` → `unknown` over a `live` that
    really refuses the fast-forward, and asserts the arm's message.
  - Red before the fix on the freshness assertion. Green after.
- **Fixed, comment.** The comment above the tier guard loop in
  `gitlore_sync_memory_to_live` now says the guard restamps on none of its arms,
  because it does not report which arm failed. It names the arms that prepare
  nothing, and the residual (an earlier tier's recovered up projection leaves
  the approval stale).
- **Recorded for decision, first question.** Should guard arms that prepare
  nothing restamp? That needs the guard to return a distinct status per arm.
  Recommendation: yes, via a distinct return code from
  `gitlore_guard_stale_merge_state` for the report-only arms (orphaned
  MERGE_HEAD, unclassifiable state, failed recovery checkout).
- **Recorded for decision, second question.** A restamp at failure time also
  blesses a concurrent write made before it. Recommendation: accept it as a
  stated residual in `git-hooks.md`, since the success path has the same window
  up to `add -A`. The alternative is to snapshot the store's newest mtime at the
  freshness check and restamp to that time with `touch -r`/`-t` rather than to
  now.

## code m4 — `push_or_report` exits before `rest_unadopted_tier`: recorded

No change. A local fix is not uniform:

- After a failed origin push, `live` equals HEAD, so resting the tier on its pin
  is safe and makes it adoptable.
- After a failed local `HEAD:live` push, `live` does not hold the merge. Resting
  would orphan the merge commit (only the reflog would keep it).

Question: per-arm behaviour? Recommendation: return a distinct status from
`push_or_report` instead of exiting. Then rest the tier after an origin-push
failure. After a local-push failure, keep it on the merge and print the
`push . HEAD:live` remedy. Name that third resting exception in `tier-stores.md`
and the changelog. This overlaps Majors 1 and 2 (`rest_unadopted_tier`, the
`compose_merged_indexes` call), so decide it with them.

## code m5 — ahead-of-pin remedy under-specified: fixed

- `scripts/lib/index-compose.sh`: the remedy now says to replace every line of
  root `MEMORY.md` whose link starts with `<tier>/` by the carrier's lines,
  prefixed, keeping no `<tier>/` line the carrier lacks. The comment is updated
  to match.
- `tests/index_compose.bats` (the ahead-of-pin case): added an assertion on the
  "replace every line of … whose link starts with 'ddaanet/'" wording.
- Red before the fix, green after.

## test m1 — hook concurrency never races: fixed

- `tests/cc_hook_index_compose.bats` concurrency case: an `mv` PATH stub barrier
  holds each relay install until both writers have arrived (bounded poll, 5 s).
  The comment is rewritten.
- Mutation (count-then-create name, hard-coded `sync` tag; script at
  `/tmp/claude-1000/mut-count.py`):
  - without the barrier: green (reproduces the finding);
  - with the barrier: red (`n_sync=0`, `mv: cannot stat … .tmp`).
- Real code with the barrier: green.

## test m2 — approval rule pinned on one arm: fixed

Four new cases. Each is green on real code and red under its mutation, and every
mutation was restored.

- `commit_memory.bats`
  `a tier commit that fails after composing keeps the approval for the retry`:
  red with the failed-tier-commit `touch` removed.
- `commit_memory.bats`
  `a memory commit that fails after composing keeps the approval for the retry`:
  red with the memory-commit `touch` removed.
- `commit_memory.bats`
  `a landing record does not adopt a foreign commit stacked on the landed one`:
  red (retry exits 0) with `[ "$parent" = "$recorded" ]` removed.
- `git_hook_pre_commit.bats`
  `a commit half-landed in a tier retries to completion from the hook`: red with
  the `add -A` restamp removed, and red with `gitlore_stage_landed_tiers`
  removed.

The shared `write_sync_driver` helper was added after its users. The existing
`a commit that fails after composing…` case now uses it too.

## test m3 — occupied-name refusal and drain `-type f` uncovered: fixed

- `index_sync.bats`
  `relay_write refuses a final name already occupied, by a report or a directory`
  (frozen `date`): red with the `-e` block deleted.
- `index_sync.bats`
  `relay_drain frames no block for a directory on a relay name`: red with
  `-type f` dropped.

## test m4 — relay id sanitization unpinned: fixed

- `index_sync.bats`
  `relay_write sanitizes the session and agent ids into one name inside the gitdir`:
  red with raw ids spliced (the write fails).

## test m5 — session-start unreadable marker never reached: fixed

- `cc_hook_session_start.bats`: added `[ ! -e "$marker" ]`, and rewrote the
  stale comments.
- Red under the Major-M2 mutation (unconditional sanitize at the drain's session
  line); green on real code.

## test m6 — RED-phase narration: fixed, except inside Major tests

- Rewritten in present tense:
  - `index_sync.bats`: section header, cases 1, 3, 4 and 5, and the case at
    ~736; also a false mutation description in case 4 (a `rm -f "$marker.tmp"`
    that the drain does not have);
  - `cc_hook_session_start.bats`: helper comment, drain case, sweep case;
  - `cc_hook_index_compose.bats`: `sync_feed` comment (false `session_id`
    claim), ~214, ~266.
- Removed the stale root skips from the two failed-relay-write cases.
- **Skipped (overlaps a Major):** the narration inside the two "leaves a marker
  in place" cases (`index_sync.bats` ~768, `cc_hook_index_compose.bats` ~290)
  and inside the empty-session case (`index_sync.bats` case 6).

## test m7 — add-tier-batch `|| agent_id=""` untested: fixed

- `cc_hook_add_tier.bats`
  `add-tier hook: an unparseable payload still mounts and drops the bare compose baseline`:
  red (hook exits non-zero) with the fallback removed.

## test m8 — no spaced-root case: fixed, plus one defect found

- `commit_memory.bats`
  `a half-landed tier commit retries to completion under a project path holding a space`
  re-roots `TMP_REPO` under `gitlore test.XXXXXX`. It is born green (the code
  was already safe) and red with `[ -f $landing ]` unquoted.
- **Defect found and fixed.** The take's staging-failure remedy in
  `gitlore_adopt_tier_into_root` (the staging arm, not the walk-back arm)
  printed `git -C "memory"`, relative to the project root.
  - It now prints the absolute path.
  - New `merge_memory.bats` case
    `a take whose pair cannot be staged prints a staging command that runs from anywhere under a spaced root`
    uses a `git` shim, extracts the printed command and runs it from `/`.
  - Red before the fix (not absolute), green after.
- `resolve_recovery.bats` staging-failure case: now also runs the printed
  command from `/`. Red when the path is made relative.
- **Not added:** assertions on the walk-back and `rest_unadopted_tier` remedies,
  which Majors 1 and 2 will change.

## test m9 — non-final `[[ ]]` under bash < 4.1: recorded

House style; no change. Question: adopt `[[ … ]] || return 1` for non-final
assertions? Recommendation: no suite-wide sweep. Apply it only when a case is
touched, if the style is adopted at all.

## prose m1 — "every later failure restamps it": fixed (doc side)

- `git-hooks.md` narrowed: a failure that prepared no merge restamps. The tier
  stale-merge guard's residual is stated.
- The second counter-example is fixed in code (code m3).

## prose m2 — "only consumer / reader" omits SessionStart: fixed

- `index-authoring-sync.md`: heading is now "One `PostToolBatch` drainer".
- Also updated: the `design.md` hub bullet, the relay changelog entry, the
  `cc-platform.md` pointer, and the comments in `index-compose.sh` and
  `index-sync-post.sh`.

## prose m3 — D50 invariant stated too broadly: fixed

- `git-hooks.md`: the take rests the tier; the continuation rests it only when
  it exits 0 onto a pin the merge contains; a yield and an off-side pin leave
  the tier in place.
- `merge-state-recovery.md`: "the shape D50 requires … but the commit path's own
  landed tier commit". The "therefore" sentence is reordered back after its
  reason.

## prose m4 — unadopted continuation "publishes": fixed

- `tier-stores.md`, the changelog entry and the `changelog.md` index bullet.

## prose m5 — named rejections missing from nodes: fixed

- `git-hooks.md` Rejected section: composing a clean store; reporting a
  non-empty commit-path compose; leaving a tier whose adoption failed ahead of
  an unstaged pin (also added to `decisions.md`'s D50 line).
- `cc-platform.md` Rejected section: relaying in place of the subagent's own
  emission.
- The walk-back rejection records the current design; Major 1 may revisit it.

## prose m6 — "shares the pre-image's key": fixed

- `index-authoring-sync.md`.

## prose m7 — pin rule callers under-enumerated: fixed

- `index-composition.md`: `gitlore_compose` itself (`PostToolBatch`,
  `SessionStart`, after a tier mount) plus the commit path's own pre-check.

## prose m8 — configuration.md gitdir list: fixed

- Added the per-session budget and upgrade nudge markers, and the keyed
  pre-image and stamp files.
- The drain wording now names `relay-drain.sh` and `SessionStart`.

## prose m9 — hub bullet links: fixed

- `design.md` links `index-authoring-sync.md` and `cc-platform.md`.

## prose m10 — changelog loose list: fixed

- Blank lines between the 2026-09-13 bullets removed.

## Outcome counts

- Fixed: 20 (code m1, m2, m5; test m1–m8; prose m1–m10). Code m3 is part fixed
  and counted under recorded.
- Recorded for decision: 3 (code m3 residuals, code m4, test m9).
- No change needed: 0.
- Skipped, overlaps a Major: 0 whole items (parts of test m6 and m8 skipped, as
  noted).

## Checks that passed

- `scripts/lint-shell.sh` (via `just lint`): 138 files clean.
- Bats, each file whole and sequential, plan line matching the pass count:
  - `index_sync`: 89/89;
  - `cc_hook_session_start`: 25/25;
  - `cc_hook_index_compose`: 25/25;
  - `cc_hook_add_tier`: 12/12;
  - `index_compose`: 65/65;
  - `commit_memory`: 28/28;
  - `git_hook_pre_commit`: 19/19;
  - `merge_memory`: 23/23;
  - `resolve_recovery`: 23/23;
  - `cc_hook_memory_commit_batch`: 10/10;
  - `cc_hook_post_tool_use`: 11/11;
  - `resolve_compose`: 8/8;
  - `tier_divergence`: 19/19;
  - `tier_lockstep`: 14/14;
  - `push_memory`: 12/12;
  - `pre_push_hook`: 9/9;
  - `integration_gitlink_staging`: 4/4;
  - `integration_memory_gate`: 2/2;
  - `plugin_distribution`: 15/15.
- `just format-docs`.
- `python3 scripts/check-docs-links.py`: exit 0.
