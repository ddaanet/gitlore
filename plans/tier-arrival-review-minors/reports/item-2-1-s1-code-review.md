# Item 2.1 / Slice 1 — code review

Scope: `gitlore_push_stores` in `scripts/lib/resolve.sh` at 50405f0 — the
removed behind-arm retry, the post-loop publication pass, the two updated
comments.

## Spec conformance

Conforms on every point checked.

- The pass sits after the tier loop and before the `remote_url` check, so a
  memory with no remote still publishes every tier.
- It skips a tier with no checkout (`[ -e "$tierpath/.git" ]`) or no local
  `live` (`rev-parse -q --verify live`), with the loop's own guards.
- It pushes when `live` is not an ancestor of `origin/live`. A missing
  `origin/live` resolves to an empty `origin_live` and pushes. A
  `merge-base` error (exit 128) also pushes, which is the safe side.
- It prints the "failed, and not because of divergence" wording and returns 1
  on a failed push. Item 2.2 owns the classification.
- A tier with no remote or a stale merge state never reaches the pass: the
  loop has already returned 1.
- errexit: `origin_live=$(…) || origin_live=""`, `|| continue` and `if !`
  guard every command whose status can be non-zero. `gitlore_git` wraps the
  push, as the loop's push does. Tier paths are double-quoted throughout, and
  names come from the same `IFS= read -r` over `gitlore_tier_paths` as the
  loop. No bash 3.2 or BSD issue.

## Interactions

- **No needless re-push (verified).** A probe had a stub `git` log every
  `push -q origin live`, with one tier ahead of its remote. `aa` was pushed
  exactly once, and the pass skipped it. A submodule checkout carries
  `+refs/heads/*:refs/remotes/origin/*`, so the loop's successful push moves
  `origin/live`, and the pass's ancestry check sees it.
- Nothing between the loop and the pass depends on the behind arm's tier
  having been pushed. The only step between them is the loop ending.
- The ahead-of-HEAD arm pushes its own tier in-loop after its take. A repair
  that take makes to a later tier is pushed by that tier's own iteration. A
  repair to an earlier tier is left to the pass. The diverged arm and the
  other arms return 1 before the pass, and nothing from them needs
  publishing.

## Findings

### MAJOR — needs a decision, not fixed: a behind-arm repair is no longer published when a later tier's push fails

**Reproduced.** Two probe tests were appended to
`tests/push_behind_vs_diverged.bats`, run with `--filter PROBE`, and then
removed.

- Setup: tiers `aa` then `bb`. `aa`'s remote gets a duplicate-bullet fact from
  `push_tier_fact`, so `aa` is behind and its take repairs `aa` itself. `bb` is
  ahead of its remote, and that remote's `pre-receive` rejects every push.
- At 50405f0: status 1. The output includes
  `gitlore: tier 'aa' — the repair is committed in its local 'live', and this push publishes it.`
  followed by `bb`'s failure. `aa`'s local `live` (5a64f3f) is not on `aa`'s
  remote (7b11400).
- Same probe with the pre-change `resolve.sh` (`50405f0~1`): status 1, same
  message, and `aa`'s remote equals its local `live`. The removed retry had
  published the repair.

**Impact.**

- The repair message is false on this path.
- The repair stays local until the next push that gets past `bb`.
- Meanwhile another consumer of `aa` can make its own repair, and the two meet
  as a divergence.
- The lockstep (D17) still holds, because memory's push is not reached either.

The message was already false on some paths before this slice:

- a take that repairs one tier and then returns 1 on another;
- the ahead-of-HEAD arm's repair followed by a `gitlore_check_head_live_agree`
  failure.

This slice adds the behind arm's own tier followed by any later failure in the
loop. The outline's claim that the pass "covers the current tier, as the retry
did" does not hold on this early-return path.

**Why it is not fixed here.** Each cheap fix conflicts with the spec or with
the next item.

1. **Reinstate the in-arm push for the current tier alongside the pass.** This
   restores the pre-change behaviour, but the runbook says the retry "is
   removed". It also changes what Item 2.2 slice 1 exercises: that stub fails
   the *second* `aa push -q origin live`, which would then be the retry instead
   of the pass.
2. **Run the pass on the loop's failure returns.** This would publish a repair
   that its take could not adopt. Test :404 ("a repair resting on a root
   problem … publishes nothing until it is fixed") pins that such a repair
   stays local.
3. **Accept the behaviour and reword.** Phase 7.2, which rewrites
   `tier-arrival-repair.md:92-98`, would then have to say that a push failing
   on a later tier leaves the repair for the next push. The message itself
   could name that condition.

Recommendation: option 3, with a test pinning the chosen behaviour. The
failure the reader already sees sends them to push again, and that push
publishes the repair. Option 1 costs Item 2.2's test design. The decision
belongs to the orchestrator or my human partner.

### MINOR — fixed: the pass's comment described only the cross-tier race

The comment said the pass catches a repair to "a tier whose iteration already
finished". The pass is also now the only publisher of the behind arm's *own*
tier's repair, the :376 case. The comment now names both cases and states
that the loop's pushes move `origin/live`, so a tier already out is not
pushed again.

### Note — scheduled elsewhere

`docs/references/tier-arrival-repair.md:92-98` still describes the behind arm
"which pushes the tier again". Phase 7.2 schedules that rewrite, so it is left
untouched here.

The other two comments are present tense and carry no plan, slice or line
identifiers.

## Mutation run

The pass was removed in place, `tests/push_behind_vs_diverged.bats` was run,
and `resolve.sh` was restored. Result: 14 passed, 3 failed.

- :376 "a repair taken by the behind arm is published before memory records
  it" (hook snapshot mismatch)
- the two new mid-loop tests (`status -eq 0`)

`git status --short scripts` was clean after the restore. The probe tests were
also removed, and `tests/` was clean.

## Files changed

- `scripts/lib/resolve.sh`: the comment above the post-loop pass (no code
  change).

## After fixes

- `shellcheck -x scripts/lib/resolve.sh`: clean.
- `scripts/run-bats.sh tests/push_behind_vs_diverged.bats`: 17 passed, 0
  failed.
- `scripts/run-bats.sh tests/push_rejection_discriminator.bats`: 9 passed, 0
  failed.
