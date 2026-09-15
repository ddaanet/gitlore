# Item 4.1 — code review

Commit reviewed: `650ec53`. Fixes applied in the working tree, uncommitted.

## Findings

### Major — the remedy's second line strands the merge when the first fails (fixed)

The printed remedy was two independent lines: `push . HEAD:live`, then
`checkout --detach <pin>`. If the push is refused again (the lock still held, or
a local hook), running the next line anyway checks out the pin. The merge commit
is then reachable only through the reflog, which is the outcome the rest guard
exists to prevent. Confirmed red with a new test (below): the checkout line
exited 0 and moved the tier off the merge.

Fix (`scripts/resolve.sh`, `rest_unadopted_tier`): the second line re-asks the
guard's own question before moving:

    gitlore:   git -C "<abs>" merge-base --is-ancestor HEAD live && git -C "<abs>" checkout --detach <pin>

Still two lines, still verbatim-runnable from any cwd, and still in the right
order (push first while HEAD is the merge). The exact-text assertion in "a
refused local live update leaves the unadopted tier on the merge with a runnable
remedy" is updated to match. **This departs from the runbook's pinned text.**
Any later prose item (S5/S6) that quotes the remedy must use the new second
line.

On the lock question: yes, `push . HEAD:live` is refused again while the lock is
still there, and git's error names the `live.lock` path. That is fine now that
line 2 can't run past that failure.

### Minor — header comments (fixed)

- `rest_unadopted_tier` said a status-2 refusal "at either continue-after-merge
  push site" can reach the rest with `live` short of HEAD. Only the local
  `HEAD:live` site can: at the origin site the local push has already succeeded,
  so `live` equals HEAD. The comment now names the local site and says why the
  second remedy line is safe to run after a repeat refusal.
- `push_or_report` said "each caller has its own commit state to unwind".
  `check_store_gates` has none. Reworded: it never exits, so a caller holding a
  landed tier merge can rest that tier before exiting on status 2.

## Checked, no change

- **Other callers:** `git grep push_or_report` outside `plans/` finds only the
  four sites in `scripts/resolve.sh`. No hooks or libs call it.
- **errexit:** the old `if ! push_or_report` already suspended errexit in the
  body, so `|| rc=$?` changes nothing there. The body is a capture inside `if`,
  a `case`, `gitlore_say_for_agent_or_user`, then `return 2`. Nothing in it
  relied on errexit to abort. It can only return 0, 1 or 2, and every caller
  branches on 1 and 2 with 0 falling through to success.
- **Continuation, local push status 2:** the merge commit has landed, the state
  file and pending ref are cleared, and `live` is unmoved.
  - With an unadopted tier, the tier stays on the merge and the remedy prints.
  - Otherwise it exits 1 with git's message, as before, and the next gate run
    retries `HEAD:live`.
  - Of the `rest_unadopted_tier` call sites, this is the only one that reaches
    the guard's refusal.
- **Continuation, origin push status 2:** `live` holds the merge, the tier rests
  on its pin, and the existing "back on the commit … run /gitlore:merge" line
  prints (test 1).
- **"then fix the problems listed above":** on the one path that prints it, the
  index problems appear earlier in the same run. `compose_merged_indexes` prints
  "the root index could not take tier …'s lines" and lists them before the
  commit. The push refusal follows, and the remedy's first line handles it.
  Acceptable as worded.
- **Guard:** `rev-parse -q --verify live` covers a missing ref. A
  `merge-base --is-ancestor` error (128) counts as "not held", which is the safe
  side. `abs` is absolute (`cd && pwd`, with CDPATH unset), the pin is the full
  sha from `rev-parse -q --verify :<tier>`, and the path is double-quoted, so
  spaces are safe. A `"`, `$` or backtick in the path would break the paste. The
  existing checkout-failure remedy has the same limit.
- **Idiom:** stderr `printf`/`echo`, matching the surrounding rest messages.
  bash 3.2 clean, no `2>/dev/null`. The duplicated
  `[ -z "$tier_unadopted" ] || rest_unadopted_tier …; exit 1` tails are
  one-liners, and a helper would hide which exit each arm takes. Left as is.

## Test added

`tests/resolve_compose.bats`: "the remedy keeps the tier on the merge while its
local live update is still refused". It reproduces slice 2, keeps the lock held,
and runs both remedy lines. It asserts that each fails and that tier HEAD is
still the merge. Red on `650ec53` (the checkout line exited 0), green after the
fix.

## Verification

- `shellcheck -x scripts/resolve.sh`,
  `shellcheck -x tests/resolve_compose.bats`: clean.
- `scripts/run-bats.sh`, one file at a time:
  - `tests/resolve_compose.bats`: 22 passed
  - `tests/tier_divergence.bats`: 19 passed
  - `tests/resolve_recovery.bats`: 23 passed
  - `tests/pre_push_hook.bats`: 9 passed
  - `tests/push_rejection_discriminator.bats`: 9 passed
  - `tests/git_hook_pre_commit.bats`: 20 passed
  - 0 failed in every file.

## Flags

- REFACTOR-NEEDED: none
- UNFIXABLE: none
