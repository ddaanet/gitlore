# Item 1.1 slice 3 — code review

Dispatch (d). Subject: the compose call site `956e4e3` put inside
`gitlore_sync_memory_to_live` (`scripts/lib/resolve.sh`) — the `case` over
`gitlore_compose`'s status, its two message pairs and its comments.

Verdict: two major findings, both reproduced and both fixed in place; one minor
(a silently-ignored fourth status) fixed; one structural finding flagged, not
fixed. Both test files are byte-identical to `956e4e3`
(`git diff --exit-code tests/` clean). `scripts/lib/resolve.sh` is the only
changed file.

## Major 1 — the rc-2 abort preserves the summary file but not the approval

The arm's own comment claimed "this aborts without touching `$msgfile`: the
approved summary survives for the retry". The file survives; the approval does
not, whenever the partial pass wrote anything before failing — which is what
"partly composed" means.

`gitlore_commit_msg_freshness` (`scripts/lib/util.sh:275`) compares the
msgfile's mtime against the newest mtime under `$mempath`, tier worktrees
included. A compose that writes tier A's carrier and then fails on tier B
returns 2 with A's carrier newer than the summary — so the retry reads
`fresh = no` and takes the FR11 branch a few lines above, which is precisely
"the retry loses the user's approval" that the runbook names as the thing the
abort must not cause. It is not an exotic shape: a single-tier store hits it too
when the tier carrier writes and the *root* index write fails
(`scripts/lib/index-compose.sh:844-847`).

The committed test passes because its induction makes the *first* write fail, so
nothing is restamped and the promise holds by accident; it asserts the file's
presence, never its freshness.

**Reproduced, on the entry point where the msgfile is the approval.**
`commit-memory.sh` rewrites the msgfile from `-m`/`-F` on every run, so the loss
only bites the pre-commit hook path. Two tiers, root disagreeing with both
carriers, `chmod a-w memory/beta`, driven through
`scripts/git-hooks/pre-commit`:

| | committed code | after the fix |
|---|---|---|
| abort status | 1 | 1 |
| msgfile | present | present |
| freshness after abort | **no** | yes |
| retry (no new approval) | **1** — "memory is dirty and has no approved commit summary…" | 0 |
| memory HEAD after retry | **unmoved** | moved, both facts committed |

The "after the fix" column is a real second hook run with no new summary: the
approved commit lands.

### The fix

`touch "$msgfile"` on the rc-2 path, before `return 1`, with the reasoning in a
comment. It restores the state the run started from and nothing more: reaching
that arm means `fresh` was already `yes`, so the restamp can only ever turn
`yes` back into `yes`, and any *user* edit made between the abort and the retry
still reads stale because freshness is re-evaluated then. The justification that
this is not a bypass of the freshness gate is the outline's own invariant for
the dirty-only scope — a carrier is a projection of root index lines the
approved summary already covered, never new content.

The rc-2 agent remedy also *caused* the loss unconditionally: it said "then edit
MEMORY.md or memory/.gitlore-tiers again to retrigger composition and retry",
and following that instruction restamps a memory file and guarantees the stale
read even in the sub-case where the approval would have survived. That clause is
the `PostToolBatch` hook's retrigger mechanism, borrowed from
`gitlore_compose_and_report`'s `ctx` text where it is correct; at this call site
the retrigger is the retry itself. Replaced with "then retry the commit — the
approved summary is still in place and the commit path composes again", which is
now true because of the restamp.

## Major 2 — the rc-1 report prints a remedy the same run invalidates

`gitlore_compose_check_pins` does not emit a generic complaint: its problem line
carries a verbatim command,
`` Return it to the pin with `git -C "<abs>" checkout --detach <pinned>` ``
(`scripts/lib/index-compose.sh:341`). The rc-1 arm forwards that line and then
falls through to `gitlore_sync_tiers_to_live` and `add -A`, which stage the
tier's *moved* gitlink. By the time anyone reads the message, `<pinned>` is no
longer what the memory store records.

**Reproduced** with the realistic shape — a tier moved off the pin with a clean
worktree, the way a hand-run `git pull` inside it leaves things:

```
pinned-before=6b0e4615…   tierhead-before=34ce3f46…
stderr: … Return it to the pin with `git -C "…/memory/ddaanet" checkout --detach 6b0e4615…`
pinned-after=34ce3f46…    tierhead-after=34ce3f46…      ← the commit adopted the move
second compose: rc=0, "composed memory/ddaanet/MEMORY.md"
carrier: "upstream fact"  →  "root's older text"
```

So the refusal fires once, reports, and the commit then removes the condition
that made it fire; the next composition — SessionStart, or an edit through the
`PostToolBatch` hook — projects root's older text over the carrier without
refusing. That is the destruction of approved upstream facts D31/D36 exist to
prevent, delayed by one commit.

**The adoption is not this slice's doing** and is not a regression: `add -A`
predates all of item B, and before the commit path composed at all the same
sequence ended in the same overwrite at the next SessionStart. What is new — and
in scope — is a message that presents a stale remedy as current.

### The fix (messages), and what is flagged instead

In scope: the rc-1 arm now says the commit stages each tier at the commit its
worktree is on now, so a pin figure printed above is the one from before it, and
that composition runs again at the next memory commit. The "edit MEMORY.md … to
retrigger composition" clause is gone here too — post-adoption that edit would
*perform* the overwrite rather than repeat the refusal.

Out of scope, flagged for the Phase 1 boundary checkpoint: whether the commit
should adopt an off-pin gitlink at all. Fixing it means either aborting on a
pin-mismatch rc 1 (which contradicts the runbook's explicit "commit proceeds")
or excluding the refused tiers from the memory `add -A` (structural, and it
touches the staging the `GIT_INDEX_FILE` handoff depends on). Both are design
calls, not review fixes. Recommendation: record it as a decision or a known
residual rather than patch it here.

## Minor — the fourth status was silently ignored

`gitlore_compose` (`scripts/lib/index-compose.sh:800-853`) returns 0, 1 or 2 and
nothing else: every exit is an explicit `return`, so no internal command's
status leaks out. A fourth status is therefore unreachable from its own code —
but the `case` had no default, so any status the call site did not recognise
fell through to the commit in silence, which is the exact failure mode the slice
exists to remove, and one edit to `gitlore_compose` away from being real.

Added a `*)` arm: it reports the status and the captured output, restamps the
summary for the same reason rc 2 does, and aborts — an unrecognised status
carries no fail-safe promise, so it is treated as the partial write it might be.

## Also changed — the duplicated header literals

Each arm repeated its header sentence in both `gitlore_say_for_agent_or_user`
arguments, four literals for two headers, so the two arms could drift silently.
Each header now lives in one `local` variable interpolated into both, which also
drops the `$(printf …)` wrappers in favour of the multi-line string literals the
rest of this file uses for git's own output. Both headers remain byte-identical
to `gitlore_compose_and_report`'s (`scripts/lib/index-compose.sh:779,787`),
checked against the source, and the four substrings the slice's tests assert are
unchanged.

The rc-1 text also dropped "with the stale carrier as-is" for "with the memory
indexes as they stand": a `gitlore_compose_check` refusal (a broken index line,
an unmounted listed tier) has nothing to do with a stale carrier, and the arm
serves both refusal kinds.

## Checked and sound — no change made

- **The status really is `gitlore_compose`'s.**
  `local compose_result compose_rc=0` is on its own line ahead of the
  assignment, so no `local x=$(…)` masking; the assignment's own status is the
  command substitution's. Confirmed behaviourally rather than only by reading:
  rc 1 and rc 2 both arrive at the right arm through both entry points in the
  probes above.
- **Errexit does not change the reading.** `|| compose_rc=$?` suspends errexit
  through `gitlore_compose`'s body exactly as the `|| true` it replaces did, so
  compose's internals see the option context slice 1's review already
  established. Both entry points run `set -euo pipefail`; the hook calls this
  function behind `|| exit $?`, `commit-memory.sh` calls it bare, and rc 2
  produced status 1 with the message intact on both.
- **Trailing-newline stripping is harmless.** `$compose_result` loses compose's
  final newline; the header/`$compose_result`/remedy composition puts each on
  its own line and `gitlore_say_for_agent_or_user` re-adds the terminator. The
  real stderr in the probes shows no blank line and no run-together line.
- **The rc-2 `return 1` lands early enough and leaves nothing behind.** It
  precedes `gitlore_sync_tiers_to_live`, the memory `add -A`, the commit and the
  `rm -f "$msgfile"`; memory HEAD is unchanged in the probe. Nothing is staged
  (no `add` has run yet), no lock is taken, no `MERGE_HEAD` is written — the
  only residual is the partly-composed carrier on disk, which is what the
  message reports. The per-tier and per-store stale-merge guards that ran
  earlier may have *repaired* a `stale-no-merge-head` state; that repair is
  idempotent and correctly left in place. `gitlore_commit_notified_file` is
  deliberately not cleared: memory is still dirty, so the nudge episode is not
  over.
- **Ordering against slices 1 and 2 is untouched.** The `case` replaces one
  statement in place — after the freshness read, after the per-tier stale-merge
  guard, inside the `dirty = 1` branch, before the tier sync. Slice 1's mutation
  evidence (compose moved after `gitlore_sync_tiers_to_live` reds both cases)
  and slice 2's clean-store negative both still hold;
  `tests/git_hook_pre_commit.bats` is green.
- **Whitespace and portability.** Every expansion is quoted, including
  `case "$compose_rc"`, `"$compose_result"` and `touch "$msgfile"`; nothing is
  split on whitespace. `touch` with no flags is POSIX and identical on BSD. No
  bash-4 construct, no GNU-only `sed`/`find`/`stat`/`grep`/`mktemp`. bash 3.2
  safe; `local` inside a `case` arm is function-scoped and fine there.

## Test evidence

- `scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`
  → 29 passed, 0 failed.
- `scripts/run-bats.sh tests/integration_gitlink_staging.bats tests/git_hook_memory_pre_commit.bats tests/index_compose.bats`
  → 70 passed, 0 failed.
- `shellcheck -s bash scripts/lib/resolve.sh` → clean. `just lint` →
  `lint-shell: 137 files clean`.
- **Mutation, in place, restored.** rc-2 arm's `return 1` removed:
  `not ok 13 a compose write failure aborts the commit` on
  `[ "$status" -ne 0 ]`, 12 passed 1 failed — so the restructured arm is still
  what the slice's test discriminates on. A second in-place mutation (the
  `touch` removed) produced the "committed code" column of Major 1's table.
  `scripts/lib/resolve.sh` restored after each; `git status --short` carries
  only this review's edit, and the three scratch `.bats` probes were deleted in
  the same call that ran them.

## Coverage this review could not add

Both test files are out of scope, so three things the fixes introduce are
unasserted. Worth the orchestrator folding in:

1. **The lost approval** — the case that would have caught Major 1. Hook path,
   two tiers, root disagreeing with both carriers, `chmod a-w` on the *second*
   tier's directory: first `bash "$HOOK"` aborts, second `bash "$HOOK"` with no
   new summary commits. Needs the
   `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"` guard.
2. **The user arm.** Both slice-3 cases set `CLAUDECODE=1`, so only the agent
   text is pinned; the register fix to the rc-1 user arm (it no longer says
   "then retry" after a commit that succeeded) is unasserted.
3. **The `*)` arm** is unreachable without stubbing `gitlore_compose`, so it is
   reasonable to leave it uncovered — noted so the gap is a decision rather than
   an oversight.

## Gates

`scripts/lib/resolve.sh` changed, so `956e4e3`'s
`.git/gitlore/gates/{lint,test-unit,test-integration,check-distribution}` no
longer postdate the gated input. `lint` was re-run here and passes; the full
`just precommit` re-run is left to the orchestrator, as is the commit.

## Not touched

`tests/commit_memory.bats`, `tests/index_compose.bats`,
`tests/git_hook_pre_commit.bats`, `scripts/lib/index-compose.sh`,
`scripts/lib/log.sh`, `scripts/commit-memory.sh`,
`scripts/git-hooks/pre-commit`, `docs/`, and Phases 2 through 4.
