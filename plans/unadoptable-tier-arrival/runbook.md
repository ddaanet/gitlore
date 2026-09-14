# Runbook: the unadoptable tier arrival

Design: `plans/unadoptable-tier-arrival/outline.md` (K1–K7, S1–S7). Recall:
`plans/unadoptable-tier-arrival/recall-artifact.md`. Requirement IDs are the
outline's key decisions; the sub-problem each item implements is named in its
title.

Run constraints: bats files one at a time (`scripts/run-bats.sh <file>`), never
two suites at once; `just precommit` in the background; every store fixture from
`tests/helpers/tier-fixtures.bash` and the suite's own helpers, never a hand-run
throwaway repo. A test that holds a ref or index lock exports
`GITLORE_GIT_RETRY_SCHEDULE=0` first, as `tests/resolve_compose.bats:221` does —
`gitlore_git` otherwise retries a lock error for about ten seconds. A slice
marked **guard** already holds when it is written, because an earlier slice's
green delivers it; its red is against the pre-job code or a narrower
implementation, and the executor records it as a guard instead of forcing a red.

| Requirement | Phase | Items | Notes |
|---|---|---|---|
| K5 prevention | 1 | 1.1 | attribution helper reused by 2.2, 3.1 |
| K3 repair rules | 2 | 2.1 | |
| K1 plain commit in the take | 2 | 2.2 | |
| K2 attribution and resting | 2 | 2.2 | no-carrier arm guarded by `tests/merge_memory.bats:356` |
| K6 publication | 2 | 2.2, 2.3 | `/gitlore:push` line; fetch-first, `behind` arm retry |
| K4 continuation gate | 3 | 3.1 | inverts `tests/resolve_compose.bats:241` |
| m4 statuses and rest guard | 4 | 4.1 | minor-pass-2 code m4 |
| K2, K4, K6 agent-facing | 5 | 5.1–5.3 | |
| K7 decision records | 6 | 6.1–6.7 | D44, D49 and FR11 claims updated for the repair |
| K3 memory fact | 7 | 7.1 | index budget waived by my human partner |

## Phase 1: Prevention, S1 (type: tdd)

- Item 1.1: `scripts/lib/index-compose.sh` (new helper beside
  `gitlore_compose_check_index`) and `scripts/lib/resolve.sh`
  (`gitlore_sync_memory_to_live`, the `1)` arm of the `compose_rc` case) — the
  commit path aborts on a compose problem in an index file the commit carries
  changes to. Requirements: K5. The arm reads, per problem-bearing index,
  whether that file is dirty: a tier carrier through
  `git -C "$mempath/$tier" status --porcelain -- MEMORY.md`, root through
  `git -C "$mempath" status --porcelain -- MEMORY.md`. Tiers come from
  `gitlore_tier_paths "$mempath"`, skipping one with no `$mempath/$tier/.git` as
  the tier loop above does. Root rules 2 and 3 print no file prefix, so the
  helper's attribution to `"$mempath/MEMORY.md"` is exactly rules 1, 4 and 6. An
  abort prints, on both arms of `gitlore_say_for_agent_or_user`, the refusal
  header the arm already builds, then states that the commit was aborted because
  a problem is in an index file this commit changes, that the fix is an edit to
  the named lines, and that the summary needs approval again (the user arm ends
  as the rc 2 arm's does); it runs `touch "$msgfile"` and returns 1. Everything
  else keeps today's advisory text. The arm's comment names which problems abort
  and which report. Slices:
  1. External contract, `tests/commit_memory.bats`: "a dirty carrier with a
     duplicate pointer aborts the memory commit" —
     `make_tier_in_memory ddaanet`, `set_tier_manifest ddaanet`,
     `seed_tier_bullet ddaanet shared.md "hook"` twice and
     `seed_root_bullet "ddaanet/shared.md" "hook"`, all left uncommitted;
     `commit-memory.sh -m` exits 1, its output contains
     `memory/ddaanet/MEMORY.md: duplicate pointer path shared.md` and `aborted`,
     the tier's `git status --porcelain -- MEMORY.md` is non-empty, and memory
     `HEAD`, the tier's `HEAD` and the tier's `live` are unchanged.
     `commit-memory.sh` rewrites the summary just before the sync, so the
     restamp is slice 2's.
  2. `tests/git_hook_pre_commit.bats`: "a dirty carrier with a duplicate pointer
     aborts the commit and restamps the approval" — slice 1's fixture with the
     summary written to `gitlore_commit_msg_file memory`, then the summary and
     every file `find memory -type f -not -path '*/.git/*'` lists backdated to
     one `touch -t` stamp, so freshness reads `yes`; `bash "$HOOK"` exits
     non-zero, its output names the duplicate line, memory `HEAD` is unchanged,
     and `_gitlore_mtime` of the summary is greater than the stamp's epoch.
  3. `tests/commit_memory.bats`: "a dirty root index with a welded line aborts
     the memory commit" — root `MEMORY.md` gains, uncommitted, the line
     `- [A](a.md) — a- [B](b.md) — b`; exits 1, output contains
     `memory/MEMORY.md: line <n> welds two pointer bullets` with that line's
     number, memory `HEAD` unchanged.
  4. `tests/commit_memory.bats`: "a carrier defect in a clean tier commits and
     reports" — the tier's carrier holds `shared.md` twice, committed in the
     tier (`GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit`) and recorded
     as its pin (`commit_memory_state`), and root gains an unrelated uncommitted
     bullet; exits 0, memory `HEAD` advanced, output contains
     `the commit went ahead` and `duplicate pointer path shared.md`. Second
     test, "a tier dirty only outside its carrier commits and reports": the same
     committed defect plus an uncommitted new fact file in the tier; exits 0
     with the same output. Red against a slice-1 green that reads tier dirtiness
     without the `-- MEMORY.md` pathspec, or not at all.
  5. `tests/commit_memory.bats`, guard: "a leftover root prefix commits and
     reports even when root is dirty" — root `MEMORY.md` gains a `gone/x.md`
     bullet (rule 3); exits 0, memory `HEAD` advanced, output contains
     `gone/x.md` and `the commit went ahead`.
  6. `tests/index_compose.bats`, the helper in isolation: "problem attribution
     matches the exact file prefix" — stdin holds one problem line each for
     `my mem.d/MEMORY.md`, `my mem.d/a/MEMORY.md`, `my mem.d/ab/MEMORY.md` and a
     decoy `my memXd/MEMORY.md`, plus a rule 3 line; for `my mem.d/a/MEMORY.md`
     it prints exactly the `a` line, for `my mem.d/MEMORY.md` exactly root's
     line (not the decoy, not the rule 3 line), and for `my mem.d/b/MEMORY.md`
     it prints nothing and returns 1. The decoy fails a `grep "^$file: "`
     implementation; the space fails one that splits words.
  Interfaces:
  - `gitlore_compose_problems_in <file>` — stdin: `gitlore_compose_check`
    output; stdout: every line beginning with the literal `"<file>: "` (no
    pattern interpretation of `<file>`); returns 0 when at least one line
    matched, 1 otherwise.

## Phase 2: Mechanical repair in the take, S2 (type: tdd)

- Item 2.1: `scripts/lib/index-compose.sh` — new `gitlore_repair_index`, plus a
  sentence in `gitlore_compose_check_index`'s comment that a new rule gains a
  repair rule in `gitlore_repair_index` in the same change. Requirements: K3.
  Rules in order: welds, then interleaved non-bullet lines, then duplicates, as
  K3 states. A weld splits at the `- [` `gitlore_welded_path` finds, only when
  that path names an existing file under `<tier-dir>`, repeated until the line
  carries no further weld. Interleaved non-blank non-bullet lines inside the
  pointer region move, in order, to the start of the trailer; blank lines stay.
  Duplicates: identical lines keep the first; differing lines sharing a path
  keep the first line absent from `<pin-carrier>` at its own position, or the
  first when all or none are absent. Every other line keeps its bytes and
  relative order; every read carries `|| [ -n "$line" ]`, per the file header.
  The scratch file is written inside `<file>`'s directory and renamed over it,
  and only when an edit was made. Report lines, one per edit, exactly:
  `split a welded line before <path>`,
  `moved a non-bullet line out of the pointer block: <line>`,
  `dropped a duplicate pointer line: <line>`. Slices:
  1. External contract, `tests/index_compose.bats`: "repairing a clean index
     changes nothing" — a well-formed index, and the same index passed through
     `unterminate_index`, are each byte-identical after the call (`cmp`), stdout
     is empty, status 0.
  2. "an identical duplicate is dropped" — the second of two identical bullets
     is gone, stdout is exactly `dropped a duplicate pointer line: <line>`, and
     `gitlore_compose_check_index` on the result prints nothing.
  3. "a welded line is split before the second bullet" — with `welded_b.md`
     present in the tier directory,
     `- [A](welded_a.md) — a- [B](welded_b.md) — b` becomes two lines at the
     weld's position and stdout is exactly
     `split a welded line before welded_b.md`; "a three-bullet weld splits
     twice" — with `welded_c.md` present too, three lines and two report lines;
     each result passes the check.
  4. "a weld naming no file in the tier is left unchanged" — `- [x](z.md)` glued
     on with no `z.md`: the file is byte-identical and stdout empty. Beside it,
     guard: "a link the check does not report as a weld is left unchanged" — a
     bullet whose hook holds a bare `[x](y.md)`, with `y.md` present, is
     byte-identical.
  5. "an interleaved non-bullet line moves to the start of the trailer" — two
     non-bullet lines between bullets land, in their original order, directly
     after the last bullet and before the original trailer; a blank line between
     bullets stays where it was; one report line per moved line.
  6. "a differing duplicate keeps the line the pin lacks" — the pin carrier
     holds the first variant, the file holds both with the second later; the
     second survives at its own position and the report names the first. Rows:
     "new to both keeps the first" (the pin has neither), "known to both keeps
     the first" (the pin has both), "a pin with no carrier keeps the first"
     (`<pin-carrier>` names a missing path).
  7. "welds are split before duplicates are resolved" — a weld whose second
     bullet duplicates a later line: the result has one line for that path and
     passes the check; every unnamed line, including one with trailing spaces,
     one with non-ASCII text and an unterminated last line, keeps its bytes and
     order.
  8. "a rewrite that cannot be written leaves the file unchanged" — `<file>`
     holds a duplicate in a directory made read-only (skipped under root, as
     `tests/git_hook_pre_commit.bats:396` does); returns 1, the file is
     byte-identical.
  Interfaces:
  - `gitlore_repair_index <file> <pin-carrier> <tier-dir>` — rewrites `<file>`
    in place; `<pin-carrier>` may name a missing file (read as empty); stdout:
    one report line per edit, nothing when no edit; returns 0, or 1 when the
    rewrite could not be written (file unchanged).

- Item 2.2: `scripts/lib/resolve.sh` `gitlore_adopt_tier_into_root` — the repair
  inside the take. Requirements: K1, K2, K6. Depends on: Item 1.1, Item 2.1.
  Current state: the rc ≠ 0 arm prints the problems, checks the tier out at
  `$old_gitlink` and returns 1; "walk back" below is that checkout with its
  failure arm and today's closing message, which stays true because `live` keeps
  the arrival or R. New flow when rc is 1 and
  `gitlore_compose_problems_in "$mempath/$tier/MEMORY.md"` matches: the first
  refusal's problem list is not printed. Copy the arrival's carrier
  (`git show HEAD:MEMORY.md`) and the pin's (`git show <old_gitlink>:MEMORY.md`,
  absent when the pin has none) into scratch files under the tier's absolute
  gitdir; run `gitlore_repair_index <copy> <pin copy> "$mempath/$tier"` — the
  worktree, which is at the arrival — and walk back on its rc 1. Recheck the
  copy with `gitlore_compose_check_index`; when it prints anything, print the
  unrepairable report below, walk back and return 1. Otherwise build R: a
  temporary index (`GIT_INDEX_FILE` in the tier's gitdir) read from HEAD's tree,
  the repaired blob written with `hash-object -w` and set with
  `update-index --cacheinfo` at HEAD's mode for `MEMORY.md`, `write-tree`, then
  `commit-tree -p HEAD` with subject
  `Repair the MEMORY.md structure <tier> received` and a body of the report
  lines. Advance with `gitlore_git -C <tier> push -q . <R>:refs/heads/live`; on
  refusal print git's message, walk back and return 1. Then
  `checkout -q --detach live`, print each report line prefixed
  `gitlore: repaired <tier>'s arrival: `, and retry `gitlore_compose_up` once.
  Retry rc 0 prints
  `gitlore: tier '<tier>' — the repair is committed in its local 'live'; /gitlore:push publishes it.`
  and continues to staging and bookkeeping as today. Retry rc 1 or 2 prints the
  retry's output under today's refusal header as what adoption waits on, walks
  back and returns 1. A first rc 1 with no carrier problem, and a first rc 2,
  keep today's arm. Scratch files and the temporary index are removed on every
  path. The unrepairable report is exactly
  `gitlore: tier '<tier>' took an index the take cannot repair; it is held in the tier's local 'live' and must be fixed where it was published:`
  followed by the first refusal's carrier problems (the arrival's own lines, so
  every `line <n>` is the arrival's numbering, never the repaired copy's) with
  the `"$mempath/$tier/MEMORY.md: "` prefix replaced by `live:MEMORY.md: `. The
  function's header comment gains the repair arm. Post-state:
  `tests/merge_memory.bats:356` (a clean arrival beside a root `gone/x.md`) is
  the K2 no-carrier-problem arm and stays green unchanged — it asserts the tier
  on its pin and `live` on the arrival. Fixtures: a remote arrival is
  `push_tier_fact ddaanet "<lines>"` on the `tests/merge_memory.bats:331` setup
  — it commits in a plain clone, bypassing S1, and a multi-line argument appends
  several lines. A weld arrival also needs the file its second path names, so a
  suite-local `push_tier_files` helper in `tests/merge_memory.bats`, shaped like
  `push_tier_fact`, commits one carrier line plus named files. The local reach
  uses the `tests/merge_memory.bats:518` setup with
  `seed_tier_bullet ddaanet local.md "committed here, never recorded"` run just
  before `strand_live_ahead_of_pin ddaanet`, so the stranded commit carries that
  bullet twice. Every take runs `bash scripts/merge-memory.sh`. Slices:
  1. External contract: "a take repairs a duplicate pointer that arrived and
     adopts the repair" — exits 0; tier HEAD and `live` are one commit R whose
     only parent (`rev-list --parents -n 1`) is the arrival; R's subject is the
     repair subject and its body names the dropped line; R's carrier passes the
     check; memory HEAD records the gitlink R and root carries the tier's line
     once; output contains
     `gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line:`
     and `/gitlore:push publishes it`; the tier remote's `live` is still the
     arrival.
  2. Guard: "a take repairs a welded line that arrived" (via `push_tier_files`,
     the second path's file in the arrival) and "a take repairs an interleaved
     non-bullet line that arrived" — each exits 0 with R on top of the arrival
     and the matching report line.
  3. "a repair beside a root problem lands in live and waits" — root carries a
     committed `gone/x.md` bullet; exits 1; output contains `gone/x.md` and the
     `repaired ddaanet's arrival:` line, and no `duplicate pointer path` line;
     tier HEAD is the pin; tier `live` is R with the arrival as parent; memory
     HEAD unchanged. After deleting the root line (`sed`, as
     `tests/merge_memory.bats:375` does), a second take exits 0 with no
     `repaired` line, `rev-list --count <arrival>..live` is 1, and memory
     records R.
  4. "an arrival the repair cannot fix walks back and names upstream" — the
     arrival carries an identical duplicate bullet, then below it
     `- [a](a.md) — a- [z](z.md) — z` with no `z.md` in the tier; exits 1,
     output contains the unrepairable report sentence and
     `live:MEMORY.md: line <n> welds` where `<n>` is the weld's line number in
     the arrival (one more than in the repaired copy), tier HEAD the pin with an
     empty `status --porcelain`, `live` the arrival.
  5. Guard: "a local live that ran ahead with a defective carrier is repaired" —
     reach through `gitlore_adopt_advanced_live` with the stranded duplicate;
     exits 0 with R on top of the stranded commit.
  6. "a refused live update after the repair leaves no trace" — slice 5's
     fixture plus a held `refs/heads/live.lock` in the tier's gitdir; exits 1,
     output contains `live.lock`, tier HEAD the pin with an empty
     `status --porcelain`, `live` the stranded commit, and no line of
     `log --all --format=%s` is the repair subject. With the lock removed a
     second take exits 0 with R on top.
  Interfaces:
  - take output on a repair: one line per `gitlore_repair_index` report line,
    prefixed `gitlore: repaired <tier>'s arrival: `, printed once R is in
    `live`; when adopted, then
    `gitlore: tier '<tier>' — the repair is committed in its local 'live'; /gitlore:push publishes it.`;
    exit 0 when adopted, 1 when resting.
  - R: a commit in the tier whose only parent is the arrival, subject
    `Repair the MEMORY.md structure <tier> received`, body the report lines;
    left in the tier's `live` whether adopted or resting.

- Item 2.3: `scripts/lib/resolve.sh` `gitlore_merge_one_store` and the `behind`
  arm of `gitlore_push_stores` — the repair publishes the way its take does.
  Requirements: K6. Depends on: Item 2.2. `gitlore_merge_one_store`: the fetch,
  and the remote checks it needs, come before `gitlore_adopt_advanced_live`. The
  local adoption runs unless the fetch succeeded and local `live` is an ancestor
  of `origin/live` (both read with `rev-parse -q --verify`; a missing ref runs
  the adoption), in which case the remote fast-forward takes origin's commits.
  Every return before the ancestry test — a tier with no remote or a placeholder
  URL, a failed fetch, a remote with no `live` — runs the local adoption first,
  then prints and returns as today; `head` is read after the adoption. The
  comment above the adoption call is rewritten for the new order. The `behind`
  arm (after `gitlore_merge_stores "$mempath" || return 1`): when the tier's
  `live` is now strictly ahead of `origin/live`, retry
  `gitlore_git -C "$tierpath" push -q origin live`; a refusal prints the outer
  `*)` arm's message and returns 1; then `continue`. Slices:
  1. External contract, guard, `tests/push_behind_vs_diverged.bats`: "a repair
     taken inside a push is published before memory records it" — the
     `tests/push_behind_vs_diverged.bats:268` setup with the stranded duplicate
     of Item 2.2, and a `pre-receive` hook on `$MEMORY_REMOTE` that unsets
     `GIT_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES` and
     `GIT_QUARANTINE_PATH`, writes
     `git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live` to a file, and
     exits 0; the push exits 0, the tier remote's `live` is R, memory's remote
     records gitlink R, and the recorded sha is R.
  2. "a repair taken by the behind arm is published before memory records it" —
     the `tests/push_behind_vs_diverged.bats:234` setup with `push_tier_fact`
     sending a line twice, plus slice 1's hook; exits 0, the tier remote's
     `live` is R with the arrival as parent, memory's remote records R, the
     recorded sha is R.
  3. `tests/merge_memory.bats`: "a take fetches first and takes a repair another
     consumer published" — the `tests/merge_memory.bats:331` setup,
     `push_tier_fact` sending a line twice (arrival A),
     `git -C memory/ddaanet fetch -q origin live:live` so local `live` is A with
     HEAD on the pin, then a test-local clone of the tier remote deletes the
     second copy, commits R' and pushes `live`; exits 0, tier HEAD is R', `live`
     equals `origin/live`, and output has no `repaired` line.
  4. "a failed fetch still adopts local live and reports the fetch failure" —
     the `tests/merge_memory.bats:518` setup with a clean stranded commit and
     `git -C memory/ddaanet remote set-url origin "$TMP_REPO/missing.git"`;
     exits 1, output contains `could not fetch tier 'ddaanet'`, tier HEAD is the
     stranded commit, and root carries its line. Holds on the pre-job code; red
     against a slice-3 green that returns on a failed fetch before adopting.

## Phase 3: Continuation gate, S3 (type: tdd)

- Item 3.1: `scripts/resolve.sh` `compose_merged_indexes` — a merged index that
  fails the check does not land. Requirements: K4. Depends on: Item 1.1. After
  `gitlore_compose_up` returns 1: for a tier merge, the problems
  `gitlore_compose_problems_in "$memroot/$merged_tier/MEMORY.md"` attributes;
  for a memory-root merge, those attributed to `"$memroot/MEMORY.md"`. Any match
  prints
  `gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:`
  and the lines, then `exit 1` before any `add`. No match keeps today's arms.
  The header comment's "A refusal never blocks the merge" paragraph
  (`scripts/resolve.sh:85-90`) is rewritten to say which refusals block.
  Post-state: the existing test at `tests/resolve_compose.bats:241` ("a compose
  refusal is reported but never strands the merge") inverts in slice 4. A
  passing merged carrier beside a root-only problem still lands and rests the
  tier: `tests/resolve_compose.bats:137` asserts that and stays green unchanged.
  Slices:
  1. External contract, `tests/resolve_compose.bats`: "a tier merge whose merged
     carrier has a duplicate pointer is not committed" —
     `prepare_tier_merge_with_new_lines`, then the synthesized carrier rewritten
     with `- [their fact](t.md) — theirs` twice and
     `git -C memory/ddaanet add -A`; `resolve.sh continue-after-merge` exits 1,
     stderr contains `was not committed` and
     `memory/ddaanet/MEMORY.md: duplicate pointer path t.md`, the tier's merge
     state file and `MERGE_HEAD` exist, tier HEAD is the pre-merge commit, root
     `MEMORY.md` is byte-identical and memory HEAD unchanged. A second test for
     a `head-vs-live` tier merge, prepared as `tests/tier_divergence.bats:143`
     does, asserts the same.
  2. Guard: "a kept refused merge re-emits the continuation directive" — after
     slice 1's refusal, `bash "$RESOLVE"` in default mode exits 1 and stderr
     contains `continue-after-merge`.
  3. Guard: "a fixed merged carrier lands" — after slice 1's refusal the second
     copy is removed and staged; `continue-after-merge` exits 0, tier HEAD is a
     two-parent merge, memory `HEAD:ddaanet` is that merge, root carries
     `- [their fact](ddaanet/t.md) — theirs`.
  4. "a memory-root merge whose merged index welds a line is not committed" —
     `diverge_memory_with_index` with a welded root line, `bash "$PRE_COMMIT"`,
     then `run_stub_synth memory`; exits 1, memory's state file and `MERGE_HEAD`
     kept, memory HEAD unchanged. The test at line 241 is rewritten as "a
     duplicate in the merged root index keeps the merge unlanded", asserting
     exit 1, `MERGE_HEAD` present and memory HEAD unchanged.
  5. Guard: "a memory-root merge with only a leftover root prefix commits
     uncomposed" — merged root carries a `gone/x.md` bullet; exits 0, the merge
     commit exists, stderr contains `committed uncomposed` and `gone/x.md`. Red
     against a slice-4 green that blocks on any root refusal.
  Interfaces:
  - `resolve.sh continue-after-merge` — exits 1 before any commit when the
    merged index fails the check, stderr
    `gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:`
    followed by the problem lines; merge state and `MERGE_HEAD` kept.

## Phase 4: Per-arm exits and the rest guard, m4 (type: tdd)

- Item 4.1: `scripts/resolve.sh` `push_or_report`, its four callers
  (`continue-after-merge` at the `. HEAD:live` and `origin live` pushes;
  `check_store_gates` at both pushes), and `rest_unadopted_tier`. Requirements:
  m4. Depends on: Item 3.1. Post-state: `compose_merged_indexes` already carries
  Item 3.1's gate; this item edits different functions of the same file.
  `push_or_report` returns 2 after emitting instead of `exit 1`. Each caller is
  written `rc=0; push_or_report … || rc=$?` then branches on 0/1/2. In the
  continuation, 2 runs `rest_unadopted_tier` when `tier_unadopted` is set, then
  `exit 1`; in `check_store_gates`, 2 exits 1. `rest_unadopted_tier`, after its
  pin-ancestry check and before its checkout, checks the tier out at the pin
  only when `live` resolves (`rev-parse -q --verify`) and
  `git -C <tier> merge-base --is-ancestor HEAD live` succeeds; otherwise it
  leaves the tier on its commit and prints, with its existing absolute `abs` and
  the full pin sha substituted, the line
  `gitlore: tier '<tier>' stays on the merge commit because its local 'live' does not hold it. Run:`
  then `gitlore:   git -C "<abs>" push . HEAD:live` and
  `gitlore:   git -C "<abs>" checkout --detach <pin>`, each on its own line,
  then `gitlore: then fix the problems listed above and run /gitlore:merge.` The
  header comments of `push_or_report` ("EXITS 1") and `rest_unadopted_tier`
  ("Exit status stays the caller's") are rewritten to match. Slices:
  1. External contract, `tests/resolve_compose.bats`: "an origin push declined
     for policy rests the unadopted tier and exits 1" — the fixture of
     `tests/resolve_compose.bats:143-147`, then a `pre-receive` hook installed
     on `$TMP_REPO/.bare-ddaanet.git` that prints `declined by policy` to stderr
     and exits 1; `continue-after-merge` exits 1, stderr contains
     `declined by policy`, tier HEAD is the pin, tier `live` is the merge
     commit.
  2. "a refused local live update leaves the unadopted tier on the merge with a
     runnable remedy" — the same fixture, no hook,
     `GITLORE_GIT_RETRY_SCHEDULE=0` exported and a held `refs/heads/live.lock`
     in the tier's gitdir; exits 1, tier HEAD is the merge commit, stderr
     contains the two `gitlore:   git -C` lines with `<abs>` equal to
     `$(CDPATH= cd memory/ddaanet && pwd)` and the pin sha, and
     `/gitlore:merge`.
  3. "following the remedy adopts the merge" — after slice 2: remove the lock,
     run the two command lines (the text after `gitlore:   `) through `bash -c`
     from `$BATS_TEST_TMPDIR`, delete the root `gone/x.md` line (`sed`, as
     `tests/resolve_compose.bats:168` does), then run `merge-memory.sh`; exits
     0, memory `HEAD:ddaanet` is the merge commit, root carries
     `- [their fact](ddaanet/t.md) — theirs`.
  4. "default-mode gates exit 1 on a policy refusal" —
     `git -C memory push -q origin live`, a `pre-receive` hook on
     `$TMP_REPO/.bare-memory.git` that declines, then a memory commit through
     `approve` and `bash "$PRE_COMMIT"` so local `live` is ahead;
     `bash "$RESOLVE"` exits 1, stderr contains `not because of divergence` and
     does not contain `refused as a non-fast-forward` (the `*)` arm a caller
     treating 2 as a refusal reaches).
  Interfaces:
  - `push_or_report <store> <push-args…>` — returns 0 pushed; 1 divergence (or
    an empty refusal message); 2 after emitting git's message for any other
    refusal. Never exits.

## Phase 5: Agent-facing prose, S5 (type: inline)

Prose; the orchestrator writes it or dispatches opus.

- Item 5.1: `agents/memory-merger.md` — synthesis rules gain: one pointer per
  bullet, one bullet per line, no non-bullet line inside the pointer block; turn
  2 gains: a continuation exiting 1 with problems in the merged index means the
  merge did not land — quote those lines and stop. Requirements: K4. Depends on:
  Item 3.1.
- Item 5.2: `skills/resolve/SKILL.md` — that exit is answered with `rejected:`
  plus the problem lines and the loop continues; Summarize separates index
  problems that blocked the landing from those reported after it. Requirements:
  K4. Depends on: Item 3.1.
- Item 5.3: `skills/merge/SKILL.md` Report section — a take that repaired an
  arrival relays each edit and dropped line verbatim and says `/gitlore:push`
  publishes the repair; a repair resting on local problems relays the problems
  adoption waits on. Requirements: K2, K6. Depends on: Item 2.2.

## Phase 6: Design records, S6 (type: inline)

Prose; the orchestrator writes it or dispatches opus. Present tense, no
correction framing; citations follow the docs' own conventions.

- Item 6.1: `docs/references/tier-stores.md` — D52 (the mechanical arrival
  repair: K1 mechanism and interruption argument, K3 rules, K2 attribution and
  resting, K6 publication, K4 continuation gate); rewrite the walk-back and
  unadopted-merge paragraphs to the new truth; the adoption paragraph's "at the
  head of every take" becomes fetch-first; the rest guard is the third resting
  exception; D44's "no duplicate-pointer residue arises on any path and no dedup
  pass is needed" becomes true of gitlore's own paths, with an arrival from a
  writer outside gitlore repaired by the take (D52). Requirements: K7. Depends
  on: Item 2.2, Item 2.3, Item 3.1, Item 4.1.
- Item 6.2: `docs/references/git-hooks.md` — D50's conclusion amended (a compose
  problem in an index file the commit changes aborts, restamping the approval;
  root rules 2 and 3 and clean files report), with the wording/structure line
  linked to D52; the summary bullet at lines 15-16, the mechanism step at line
  55 ("rc 1 reports and continues") and D50's argument paragraph at lines
  147-150 ("the commit proceeds … only reported") match it. The same item
  rewrites `docs/references/commit-gate.md:54-57` ("on any failure … no agent
  action"): an index-problem abort, like an off-pin tier, needs an edit before
  the batch retry lands. Requirements: K5, K7. Depends on: Item 1.1.
- Item 6.3: `docs/references/index-composition.md` lines 116-120 — the
  continuation paragraph states that problems in the merged index block the
  landing and what still commits uncomposed. Requirements: K4, K7. Depends on:
  Item 3.1.
- Item 6.4: `docs/decisions.md` — a D52 conclusion line, the amended D50 line,
  and K7's seven rejected alternatives by name. Requirements: K7. Depends on:
  Item 6.1, Item 6.2.
- Item 6.5: `docs/design.md` — the D50 sentence at lines 230-232 gains the abort
  on a problem in a changed index file, and FR11's stated exemption (line 51)
  names the arrival repair commit beside merge and take-bookkeeping commits
  (D52). Requirements: K1, K7. Depends on: Item 6.1, Item 6.2.
- Item 6.6:
  `docs/changelog/<landing date>-an-arrival-the-root-index-cannot-adopt-is-repaired.md`
  plus its newest-first index line in `docs/changelog.md`, in the existing
  entries' shape. Requirements: K7. Depends on: Item 6.1, Item 6.2.
- Item 6.7: `docs/references/merge-and-resolve.md` — D49's "merge and
  bookkeeping commits are FR11's stated exemption" (line 306) names the arrival
  repair commit, which restructures and adds no text, linked to D52.
  Requirements: K1, K7. Depends on: Item 6.1.

## Phase 7: Memory fact, S7 (type: inline)

- Item 7.1: `memory/ddaanet/gitlore-tier-merge-direction.md` — a paragraph after
  the propagation rule per the outline's S7 text; the description gains "a
  structural defect upstream sent is the take's to repair", and the root
  `memory/MEMORY.md` line `ddaanet/gitlore-tier-merge-direction.md` gains the
  same hook. The file stays under 4KB. The parent commit's memory gate emits the
  summary protocol at commit time. Requirements: K3, K7. Depends on: Item 6.1.
