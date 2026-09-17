# Item 2.1 / Slice 2 — code review

Scope: `gitlore_push_stores` in `scripts/lib/resolve.sh` after Item 2.1. That
covers the restored behind-arm push, the post-loop pass and their comments,
reviewed as the item's net diff (`git diff 50405f0~1 f04626f`).

## Spec conformance

Conforms.

- **The restored block matches the original.** In the net diff, the behind arm
  changes only in its comment. The `merge-base --is-ancestor live origin/live`
  guard, the `gitlore_git` push, the message and `return 1` are byte-identical
  to `50405f0~1`.
- **The pass matches the spec.** It sits after the loop and before the
  `remote_url` check. It skips a tier with no checkout or no local `live`,
  pushes when `live` is not an ancestor of `origin/live` (a missing ref
  included), and prints the "not because of divergence" wording and returns 1 on
  failure. Slice 1's review verified these points, and nothing in them changed
  in slice 2.

## Double push

A tier is never pushed twice.

- A successful in-loop push moves that tier's `origin/live`, because the tier
  checkout carries `+refs/heads/*:refs/remotes/origin/*`. The pass's ancestry
  check then skips the tier. Slice 1's review confirmed this with a stub that
  logged every push.
- The retry pushes only when `live` is not an ancestor of `origin/live`. Its
  success moves `origin/live` in the same way, so the pass skips that tier too.
- A failed retry returns 1, so the pass never runs.

## Where "this push publishes it" can be false

That line is printed by `gitlore_adopt_*` (resolve.sh, `GITLORE_TAKE_IN_PUSH`
branch), before `gitlore_adopt_stage_pair_and_commit`.

**No path is newly false after Item 2.1.** The comparison is against
`50405f0~1`:

- **A repair to the behind arm's own tier:** the same as before (the retry is
  restored).
- **A repair to a later tier:** the same as before. The repair checks out `live`
  detached, so that tier's own iteration pushes it.
- **A repair to a tier whose iteration already finished:** before Item 2.1, this
  push never published it, so the message was always false. It is now published
  unless the loop returns 1 first. This path got better, not worse.

The message is still false on these paths, all present before Item 2.1. They are
notes, not fixed here:

1. A take repairs tier X, and then a later step returns 1 before X's push runs.
   That step can be the same take failing on another tier, a later tier's push
   or check in the loop, or a failed push in the pass on an earlier tier.
2. A take repairs the current tier, and then its push fails. This covers the
   behind arm's retry and the ahead-of-HEAD arm's in-loop push, and adds
   `gitlore_check_head_live_agree` failing after the ahead-of-HEAD take.
3. `gitlore_adopt_stage_pair_and_commit` fails after the message is printed. The
   take returns non-zero and the push returns 1.

In each case the reader also sees the failure that stopped the push, and the
next push that gets past it publishes the repair.
**No cheap fix confined to `gitlore_push_stores`.** Running the pass on the
loop's failure returns would publish a repair its take could not adopt, which
the test "a repair resting on a root problem … publishes nothing until it is
fixed" pins against. The message cannot be made accurate at its print site:
whether the push gets that far is not yet known there. Rewording it ("this push
publishes it once it completes") is a **design decision**, left for Phase 6/7 or
my human partner.

## Findings

### MINOR — fixed: two comments said a cross-tier repair is always left to the pass

The ahead-of-HEAD comment said "the post-loop pass below publishes that one".
The behind-arm comment said "A repair the same take made to a different tier is
left to the post-loop pass below". Neither holds for a repair to a *later* tier:
the repair checks out `live` detached, so HEAD and `live` agree, and that tier's
own iteration pushes it.

Both comments now separate the two cases:

- a later tier goes out with its own iteration's push;
- a tier whose iteration already finished goes out with the post-loop pass.

This fix also:

- removed the redundant "first" in "before a later tier's failure can return 1
  from the loop first";
- dropped "true even when", which overclaimed given the early-return notes
  above.

### Checked, no finding

- **errexit.** Every command whose status can be non-zero is guarded by `if !`,
  `|| continue` or `|| origin_live=""`. In the retry, a missing `origin/live`
  makes `merge-base` exit 128, which leads to a push, the safe side. That code
  is unchanged from before Item 2.1.
- **`gitlore_git`** wraps every push. Read-only `git` calls stay bare, as in the
  loop.
- **Quoting, bash 3.2 and BSD.** Paths are double-quoted, and tier names come
  from `IFS= read -r` over `gitlore_tier_paths`. No bash 4 constructs or
  GNU-only flags.
- **Comments** are in the present tense and carry no plan, slice or line
  identifiers. The D17 reference matches the neighbouring comments.
- **The pass's comment** names only the cross-tier case. That is accurate now
  that the retry again publishes the behind arm's own tier.

## Mutation run

The restored retry block (the `merge-base … origin/live` `if` in the behind arm)
was removed in place. The saved copy was kept under `/tmp/claude/probe.*`.

- `scripts/run-bats.sh tests/push_behind_vs_diverged.bats`: 17 passed, 1 failed.
- The failure was
  `not ok 18 a behind arm's repair survives a later tier's failure`, at line
  643:
  ``[ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$aa_live" ]``
  failed.

The file was then restored from the saved copy, and the probe directory was
removed. Afterwards, `git diff scripts` shows only this review's comment edits.
`git status --short scripts` lists `M scripts/lib/resolve.sh` for those edits
alone.

An earlier attempt did not mutate anything. `mktemp` failed on an unset
`$TMPDIR`, and the `&&` chain skipped the mutation. Its run was 18 passed on the
unmutated tree.

## After fixes

- `shellcheck -x scripts/lib/resolve.sh`: clean.
- `scripts/run-bats.sh tests/push_behind_vs_diverged.bats`: 18 passed, 0 failed.

## Files changed

- `scripts/lib/resolve.sh`: two comments in `gitlore_push_stores` (the
  ahead-of-HEAD take and the behind-arm retry). No code change.
