# Item 2.2 / slice 1 — code review

Commit under review: `cf4ccde`, `scripts/lib/resolve.sh`. Verdict: correct. One
minor fix applied (the helper's comment). Nothing UNFIXABLE, and no design call
needed.

## Findings

### Wording preserved byte-for-byte: OK

- Counted mechanically against `cf4ccde~1`. Before: 6 occurrences of the
  "failed, and not because of divergence. git said:" line and 2 of the "was
  refused as a non-fast-forward, …" line, with 8 `$tier_err"` tails. After: 2, 2
  and 4. That is one agent/user pair per branch in the helper. The removed text
  and the helper's text are the same strings.
- The agent and user arguments are still identical per branch, as they were
  before. Each message still goes through `gitlore_say_for_agent_or_user` with
  `>&2`, and git's stderr still follows `git said:` on its own line.
- Probed the extracted helper under `set -euo pipefail` from a scratch dir
  holding a glob-matching file. Inputs: tier `t *  x`, multi-line stderr with
  `*` and `[a]`, and the literal `(fetch*first)`. Stdout was empty and rc was 0.
  The tier name, doubled spaces, newlines and glob characters came through
  verbatim. `(fetch*first)` got the non-divergence wording, because the quoted
  pattern parts match literally.

### Classification: OK

`case "$tier_err" in *"(fetch first)"*|*"(non-fast-forward)"*)` matches a
substring anywhere in multi-line stderr, since `*` in `case` spans newlines. The
case subject is not glob-expanded. The helper uses the same discriminator as the
outer `case`. A policy message that happens to contain one of those
parenthesized tokens would get the divergence wording, which the spec accepts.
Noted only.

### Inner `*)` arm under `gitlore_classify_refusal`: no behaviour change

This arm is nested inside the outer `*"(fetch first)"*|*"(non-fast-forward)"*)`
arm and uses the same unmodified `$tier_err`. So every path into it carries one
of the two markers, and the helper always takes its divergence branch, which
prints the arm's former message exactly.

`gitlore_classify_refusal` (`resolve.sh:790`) never reads stderr. It prints
`behind`, `ahead`, `diverged` or `unknown` from ancestry and ref reads alone.
That means no "non-fast-forward by classification, marker-less stderr" input can
exist. The outer `*)` arm has the opposite guarantee: no marker, so it always
gets the non-divergence wording, as before. Tests
`tests/push_rejection_discriminator.bats` (9) and `tests/tier_divergence.bats`
(20) pass unchanged.

### Behind arm's retry push routed through the helper: approved

Before, a retry refused as non-fast-forward was reported as "not because of
divergence", which was wrong. The retry runs only after a take that did not
yield: `gitlore_merge_stores … || return 1` fast-forwarded or repaired on top of
what it fetched. It also runs only when `live` is not an ancestor of
`origin/live`. So `live` contains the remote's as last fetched, and a divergence
refusal really does mean the remote moved during the push. The divergence
wording is accurate there. No test pins this caller's non-fast-forward wording.
That is not needed for a routing change whose two outputs are each pinned
elsewhere, but it is noted.

### Return codes and errexit: OK

The helper's status is that of its last `printf`, so it returns 0. All four
callers still `return 1` after the call: the pass, the behind retry and the
inner `*)` arm do so directly, and the outer `*)` arm falls through to the
shared `return 1`. A failing `printf` to a closed stderr would behave exactly as
the inline code did.

### Placement and comment: fixed (minor)

The helper sits right after `gitlore_push_stores`, its user. Two problems in the
comment:

- It said the discriminator is what "gitlore_push_stores's callers already
  read". The function reads it for its own pushes, not its callers.
- It stated without condition that a divergence-shaped refusal "means the remote
  moved". That holds only because such a refusal reaches the helper after
  ancestry has left nothing to merge.

Rewrote it in the present tense, with no plan ids or line numbers.

### bash 3.2 / BSD: OK

The helper uses only `local`, `case` and quoted expansions.
`shellcheck -x scripts/lib/resolve.sh` is clean after the edit.

## Mutation check

Mutated the helper's pattern to `*"(fetch first)"*)` only, anchored to its
4-space indent. Ran
`scripts/run-bats.sh tests/push_behind_vs_diverged.bats --filter 'post-loop publication push refused'`.
It went red on the wording assertion (line 692,
`The remote moved during the push`).

A first, unanchored mutation also hit the outer `case` and went red earlier, on
the push-order precondition (line 686). It was discarded as not isolating the
helper.

Restored from backup both times. Afterwards `git diff scripts` shows only the
comment edit.

## Bats after fixes

- `tests/push_behind_vs_diverged.bats`: 19 passed, 0 failed
- `tests/push_rejection_discriminator.bats`: 9 passed, 0 failed
- `tests/tier_divergence.bats`: 20 passed, 0 failed

## Files changed

- `scripts/lib/resolve.sh`: comment on `gitlore_report_tier_push_failure`
  (uncommitted)
