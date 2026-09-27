# Code review — `d47c037`, a tier's prepared merge outranks the screens too

Reviewed: the whole commit, against `plans/tier-merge-outranks-the-screens/plan.md`,
`plans/batch-retry-approval-freshness/reports/deliverable-review.md` (M1, M2, the
third site), the recall artifact's files, and `.claude/rules/shell.md`.

The fix is correct at every site the plan names, and the suite split is a clean
move. One ordering defect was introduced by the `commit-memory.sh` loop — fixed
below. Three findings are flagged, not fixed.

## Fixes applied

### F1 (Major) — `scripts/commit-memory.sh`: the tier loop ran ahead of the freshness read

The loop was placed between the root guard and the approval screen, so it ran on
**every** invocation, including `-m`/`-F` with a summary just written. That is not
the shape the plan cited: `resolve-sync-memory.sh:42-47`, named as the model, sits
*inside* the refusal branch under `[ "$fresh" != "yes" ]`, with the comment that
states why — *"The loop below still guards the fresh path; this one only decides
which refusal speaks."*

The placement matters because `gitlore_guard_stale_merge_state` is not a predicate.
Its `stale-no-merge-head` arm calls `gitlore_recover_stale_no_merge_head`, whose
**return-0 paths write into the store**: `gitlore_git -C "$store" checkout -q
--detach "$pending"` on the interrupted-preparation and dead-merge arms
(`resolve-recovery.sh:77,95`), and `gitlore_adopt_recovered_merge` on the
already-landed arm (`:117-119`). And `gitlore_commit_msg_freshness` walks
`find "$mempath" -type f -not -path '*/.git/*'` (`util.sh:326`), which descends
into tier worktrees — a tier's `.git` is a *file*, so nothing excludes its content.

So the sequence was:

1. `-m` writes `$msgfile` at T0.
2. New loop recovers a tier, writing tier files at T1 > T0, returns 0.
3. Approval screen passes.
4. `gitlore_sync_memory_to_live` reads freshness → `no` → refuses with
   *"memory is dirty and has no approved commit summary"* — the summary the
   caller just approved, rejected, on an arm that does not restamp.

That is a wasted approval turn: precisely the defect class this commit exists to
remove, reintroduced on the neighbouring path. Before the commit the tier
recovery happened only at `resolve-sync-memory.sh:88-94`, *after* `fresh` was
computed, so a fresh approval survived it.

Fixed by moving the loop inside `if ! gitlore_approval_present "$msgfile"`, ahead
of the refusal it must outrank — the placement the plan cited. Nothing is lost on
the approved path: `resolve-sync-memory.sh:88-94` still guards every mounted tier
before the first write, so a tier's prepared merge is still handed over, just from
inside the sync. The comment now records why the loop is in that arm rather than
ahead of it. The three suites stay green unchanged (the tier test `rm -f`s the
approval before the run that matters).

### F2 (Minor) — `tests/cc_hook_memory_commit_batch.bats`: stranded `load`

`load helpers/divergence-fixtures` survived the move with zero remaining users —
`advance_branch_with_file`, `make_diverged_head_vs_live` and
`make_diverged_head_vs_remote` all left with the two merge tests. Removed, along
with the double blank line the deleted header left between the `load` block and
the first `@test`.

### F3 (Minor) — the changelog entry claimed the root store was clean

*"a tier mid-merge left the root clean"* is false and contradicts the mechanism it
is explaining: a tier's merge checkout makes the root store **dirty** (no
`submodule.*.ignore` is set anywhere in the repo, so the submodule reports
modified content), and every screen described in the paragraph is reached only
*because* it is dirty. What was clean was the root's own merge state. The plan
says it exactly — *"the root is not mid-merge"*. Reworded to say that, and the
paragraph's mixed tense (`self-heal` / `catches up` inside a past-tense account of
a fixed defect) put into the past. A clause was added noting where the
`commit-memory.sh` loop now sits, per F1. Re-run through `rumdl fmt`.

## Findings flagged, not fixed

### N1 — `scripts/lib/util.sh` is at exactly 400 lines, its cap

Confirmed from the implementing agent's own report
(`reports/item-1-1-s1-green.md:77-82`): the addition took the file 386 → 405, and
the new function's comment was trimmed to land it at exactly 400. Per the repo's
own rule, a file parked *at* its cap has stopped emitting the signal, and the
trimmed lines are the ones that would have carried the reason.

What the comment should say, and does not — **do not write it, it does not fit**:

1. **`Args: $1 = memory worktree path.`** Every other function in `util.sh` ends
   with an `Args:` line, `gitlore_store_mid_merge` included (*"$1 = store worktree
   path"*). Its absence here is not cosmetic: the two functions take *different*
   things. Passing a tier path to `gitlore_any_store_mid_merge` loops over that
   tier's own (absent) submodules and answers only for the tier — a silent
   degradation to the root-only behaviour this commit exists to remove, which
   reads as a correct call.
2. **Why `gitlore_tier_paths` and not `gitlore_active_tiers`.** The reason is
   reasoned out at `resolve-sync-memory.sh:78-82`: what this orders against is
   `gitlore_sync_tiers_to_live`, which commits inside a mounted-but-*unlisted*
   tier too. Without it, a future reader tightening the loop to the manifest
   subset reintroduces the bug for dormant tiers and every test still passes.

A third reason — why `gitlore_store_mid_merge` is kept rather than replaced
(`index-compose-check.sh:215` asks about one named store) — currently lives only
in the changelog and the plan, neither of which a reader of `util.sh` opens; it
belongs on `gitlore_store_mid_merge`, not here.

Restoring (1) alone is +1 line → 401, over the gate. Splitting `util.sh` is the
separate decision.

### N2 — RED-phase comments in the two new tier tests state the defect as current truth

`tests/cc_hook_memory_commit_batch_merge.bats:76-83` and `:110-113`, and
`tests/commit_memory_approval.bats:158-163`, describe the *pre-fix* behaviour in
the present tense: *"`gitlore_store_mid_merge` only reads the root, so this
batch's post-run screen reads mid_merge false and falls through to the freshness
arm"*; *"the pre-run screen's own 'no approval yet' arm checks mid_merge against
the root store too, misses the tier's merge"*; *"commit-memory.sh's own
stale-merge guard only checks the root store"*. None of the three is true of the
code they now run against. They read as a live description of the hook and will
mislead the next reader into thinking the guard is still root-only.

Out of scope here (test bodies), and each is one sentence to requalify — the
assertions and fixtures need no change.

### N3 — `skills/resolve/SKILL.md` attributes the directive to the pre-commit hook

`skills/resolve/SKILL.md:13` — *"**Commit-triggered**: The pre-commit hook already
emitted a merge directive"*. The batch hook's arm is a `PostToolBatch` hook, not
`pre-commit`, and it is now a routine producer of this directive. The skill still
*fires* (its `description` keys on the literal `gitlore: memory merge prepared`,
which `gitlore_emit_merge_directive` emits verbatim inside `$out`) and still
behaves correctly, since the entry-mode instruction — *"it is visible in the
output that caused you to invoke this skill"* — holds either way. Pre-existing and
out of scope; noted because question 1 asks about the consumer seam.

## Answers

### 1. The three surfaces read against each other

**The seams hold.** Checked end to end:

- **Rule → enforcer.** The plan names three sites; all three are closed, and
  there is no fourth. `gitlore_approval_present` has exactly two screening
  callers (`commit-memory.sh:75`, `memory-commit-batch.sh:98`), both now
  tier-aware. `scripts/git-hooks/pre-commit` has no screen of its own — it goes
  through `gitlore_sync_memory_to_live`, which was already tier-aware
  (`resolve-sync-memory.sh:42-47`, `:88-94`). `emit-memory-gate.sh`'s tier loop
  emits hooks and screens nothing.
- **Enforcer → consumer.** The literal `gitlore: memory merge prepared` reaches
  the agent intact: the guard's `stale-with-merge-head` arm calls
  `gitlore_emit_merge_directive`, which prints the banner on **stderr**;
  `commit-memory.sh` is invoked as `out=$(… 2>&1)`, so the banner lands in `$out`;
  the mid-merge arm interpolates `$out` into both channels. The four
  `memory merge prepared` assertions in `cc_hook_memory_commit_batch_merge.bats`
  are the lock-in. `gitlore:resolve`'s trigger string is untouched, and
  `tests/plugin_distribution.bats:126` asserts it byte-exact in the frontmatter.
- **The disjunction costs the agent nothing.** The requalified message says "the
  store or a mounted tier", but the directive it carries names the store
  outright — `gitlore_emit_merge_directive` prints `in store:` followed by the
  path, and its own comment says why (*"a tier merge and a memory merge are
  otherwise indistinguishable in the output"*). The agent is never left to guess.
- **The one seam that was wrong** was F1: the enforcer's *placement* in
  `commit-memory.sh` did not match the shape the rule cited, and the mismatch was
  invisible per-site.

### 2. `while IFS= read -r tier` with no `|| [ -n "$tier" ]`

**Safe, and the precedent is safe — for a reason specific to this producer, not
because it is precedent.**

`.claude/rules/shell.md` scopes the guard to *"every read of a file a human, an
agent `Edit` or another tool may have written"*. This is not a file read. The
input is a process substitution of `gitlore_tier_paths`, whose only output
statement is `printf '%s\n' "${rec#*$'\n'}"` (`util-config.sh:30`) — every record
it emits is newline-terminated by construction, and it emits nothing at all
(`return 0`) when there is no `.gitmodules`. There is no unterminated final line
to lose.

Note the in-loop `[ -n "$tier" ] || continue` does **not** cover this case and is
not what makes it safe: a dropped final line is non-empty. That guard skips blank
records, which the `printf` also cannot produce. Both are belt-and-braces; the
`printf` is the actual guarantee. The nine existing `< <(gitlore_tier_paths …)`
loops are safe on the same grounds.

Whitespace safety is intact independently: `gitlore_tier_paths` reads
`git config -z --get-regexp`, `IFS= read -r` preserves spaces, and every
expansion (`"$mempath/$tier/.git"`) is quoted. A tier path containing a newline
would break, which `util-config.sh:21` rules out by construction (the activation
manifest is line-oriented).

### 3. `set -e` exposure of `gitlore_store_mid_merge "$mempath" && return 0`

**Both current call sites are safe. The shape is a latent trap for any future
one.** Probed on bash 5.2 rather than reasoned:

- Called from an `if`/`elif` **condition**, errexit is suppressed for the whole
  function body: the AND-list falls through, the loop runs, and `return 1` is
  delivered to the `else` branch normally. Both sites qualify —
  `memory-commit-batch.sh:96` (`if … then mid_merge=1; fi`) and `:152`
  (`elif …`). Verified.
- Called as a **bare statement** under `set -e`, the function's `return 1` aborts
  the caller silently. Verified: the statement after the call never runs and the
  script exits 1.

`memory-commit-batch.sh` runs `set -euo pipefail` and its own comment at `:138`
shows the team already met this family of hazard, so the risk is live rather than
theoretical. This is not new with this commit — `gitlore_store_mid_merge` has the
identical shape, as does `gitlore_approval_present` — so it is a property of the
predicate family, not a defect introduced here. Left as is.

### 4. Is the requalified message true on every arm that can now reach it?

**Yes, on all four reachable shapes, and it still directs.**

| State at the arm | `$out` carries | Message true? |
| --- | --- | --- |
| Root mid-merge on entry | root guard's directive (`commit-memory.sh:72`) | yes |
| Tier mid-merge, no approval | tier guard's directive (relocated loop) | yes |
| Tier mid-merge, approval present | sync's tier guard (`resolve-sync-memory.sh:88-94`) | yes |
| Merge *prepared during* the run | the preparation's own directive | yes |

There is no shape where `gitlore_any_store_mid_merge` answers true and `$out`
lacks a directive: every path that leaves a store mid-merge either met a guard
that emitted one or is the preparation that printed one. The "already clean"
pre-screen at `memory-commit-batch.sh:77` cannot swallow a tier merge either —
no `submodule.*.ignore` is configured anywhere, so the tier's modified content
makes the root dirty.

**Still a directive.** The agent channel keeps its act — *"Act on the directive
below"* — followed by `Reason: $out`. Nothing in the requalification turned into
narration; the added words ("or a mounted tier") widen the subject of one
subordinate clause and leave the imperative untouched. The `systemMessage` is
still one lowercase line on the user channel.

### 5. Do the two doc nodes state what the code does?

**Yes — no over-claim, no under-claim.**

- `commit-gate.md` § mechanism: *"The store **or any mounted tier mid-merge**
  means the run refused to commit on top of a merge, so the guard's directive is
  the whole message"*. True for both: the batch hook's arm makes `$out` the whole
  message on the root and the tier path alike, and *"nothing was committed, no
  approval was consumed"* holds because the guard's report-only arms do not
  restamp (D53) and the bare invocation writes no `$msgfile`.
- `commit-gate.md` § screen: *"**A prepared merge on the store or any mounted tier
  outranks that screen**, on both entry points."* True on both after F1 —
  `memory-commit-batch.sh:96` screens with the tier-aware predicate, and
  `commit-memory.sh`'s loop is now ahead of its refusal and behind nothing that
  matters.
- One residue: the sentence immediately after, unchanged, still reads *"A merge
  state makes the store dirty by construction — its checkout moved the
  worktree"*. For a tier it is the *tier's* worktree that moved; the claim
  survives (the root store is dirty either way, which is what the sentence is
  used for) and is under-specified rather than wrong. Left alone — it is the
  load-bearing claim for the screen and tightening it would cost more words than
  it buys.
- `memory-entry-points.md`: *"dirty with the store or any mounted tier mid-merge →
  the stale-merge guard's directive, which runs ahead of both"*. True — the loop
  runs ahead of the absent/blank refusal and, by exiting 1, ahead of the sync's
  stale refusal.
- **The changelog entry** had the one real prose defect, fixed as F3 above. The
  rest of it is accurate: the self-heal claim holds for all three sites (each
  costs one turn, then the sync's own tier loop catches the merge), *"mirroring
  the tier loops `resolve-sync-memory.sh` already runs"* is exact, and the closing
  usage-string paragraph is right.

### 6. `scripts/lib/util.sh` at exactly 400 lines

Flagged as **N1** above, not fixed. The comment is too thin: it is missing the
`Args:` line every sibling carries — and the two functions take different
arguments, so its absence invites a call that silently degrades to root-only —
and the reason the loop reads `gitlore_tier_paths` rather than
`gitlore_active_tiers`. N1 says what each should say. Neither fits under the cap.

## The suite split, reviewed as a pure move

**Clean.** Both moved tests are **byte-identical** to their pre-commit text
(`diff -u` of the extracted blocks, empty). Nothing was lost and nothing was
silently altered.

- The shared helper `tests/helpers/cc-hook-memory-commit-batch.bash` is a verbatim
  lift of the header it replaced — `BATCH`, `setup`, `teardown`, `run_batch`,
  `ctx` — with the `SC2034` directive `BATCH` needs once it crosses a file
  boundary, and a docstring naming both consumers.
- Both halves reach their fixtures: the merge suite loads `setup`, `fixtures`,
  `divergence-fixtures` (used: `advance_branch_with_file`), `tier-fixtures`
  (used: `make_tier_in_memory`, `set_tier_manifest`) and the new helper.
  `commit_memory_approval.bats` picked up `tier-fixtures` for its new test.
- The one stranded `load` was in the residue file — fixed as F2.
- Both suites are now under the cap (303 and 138 lines);
  `check-docs-links.py` reports `oversized-file 0`.

## Verification

Re-run after the fixes, on the working tree:

- `shellcheck -x scripts/lib/util.sh scripts/commit-memory.sh
  scripts/cc-hooks/memory-commit-batch.sh` → clean, rc 0.
- `./scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats
  tests/cc_hook_memory_commit_batch_merge.bats tests/commit_memory_approval.bats`
  → **26 passed, 0 failed**.
- `./scripts/check-docs-links.py` → rc 0, **every counter 0** (141 files, 57
  decisions).
- `.venv/bin/rumdl fmt --no-cache --exclude 'plans/*/reports' docs plans` → run;
  it reflowed the edited changelog paragraph, and the result is what is on disk.
- `just precommit` → launched in the background; verdict recorded below.

Worth noting for whoever commits: the implementing agent's `just precommit`
**aborted at `check-docs-links.py`** before `lint`, `test-unit` or
`test-integration` ran (`reports/item-1-1-s1-green.md:96-107`), so the gate has
never completed on this work. This run is the first.

### `just precommit` verdict

PENDING — appended on the completion notification.
