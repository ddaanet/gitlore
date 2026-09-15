# Item 4.1 — GREEN report

Commit: `650ec53b25c8c92ebec544e068df8959f3bb453f` — "Item 4.1/1-4 —
push_or_report returns per arm and the rest guard keeps an unheld merge".

## What changed (`scripts/resolve.sh`)

- `push_or_report`: the final refusal arm now `return 2` (after emitting git's
  message) instead of `exit 1`. Header comment rewritten: "returns 2 on any
  other refusal ... Never exits."
- Its four callers rewritten `rc=0; push_or_report … || rc=$?` then branch on
  `rc`:
  - `continue-after-merge`, `. HEAD:live` push: `rc==1` keeps today's yield;
    `rc==2` runs `rest_unadopted_tier "$memroot" "$merged_tier"` when
    `tier_unadopted` is set, then `exit 1`.
  - `continue-after-merge`, `origin live` push (inside the `head-vs-remote`
    branch): same `rc==1`/`rc==2` split.
  - `check_store_gates`, both pushes (`. HEAD:live` and `origin live`): `rc==2`
    exits 1 directly; `rc==1` keeps today's `gitlore_classify_refusal`-based
    handling. Added `rc` to the function's `local` list.
- `rest_unadopted_tier`: after the existing pin-ancestry check and before the
  checkout, a new gate — `git -C <tier> rev-parse -q --verify live` and
  `git -C <tier> merge-base --is-ancestor HEAD live`. When either fails, the
  tier is left on the merge commit and the four-line remedy
  (`stays on the merge commit because its local 'live' does not hold it` / two
  `git -C "<abs>"` commands / `then fix the problems ... /gitlore:merge`) is
  printed instead of checking out. Header comment gained a paragraph explaining
  the new gate; "Exit status stays the caller's" paragraph reworded to "either
  way."
- `compose_merged_indexes` (Item 3.1's gate) untouched.

## Test order (all via `scripts/run-bats.sh tests/resolve_compose.bats --filter …`)

1. "an origin push declined for policy rests the unadopted tier and exits 1" —
   pass.
2. "a refused local live update leaves the unadopted tier on the merge with a
   runnable remedy" — pass.
3. "following the remedy adopts the merge" — pass.
4. "default-mode gates exit 1 on a policy refusal" — confirmed still passing
   (was born green).

## Suite results (each run individually, foreground)

- `tests/resolve_compose.bats`: 21 passed, 0 failed.
- `tests/tier_divergence.bats`: 19 passed, 0 failed.
- `tests/resolve_recovery.bats`: 23 passed, 0 failed.
- `tests/resolve.bats`: 8 passed, 0 failed.
- `tests/pre_push_hook.bats`: 9 passed, 0 failed.
- `tests/push_rejection_discriminator.bats`: 9 passed, 0 failed.
- Additional suites found by
  `grep -rl 'push_or_report\|check_store_gates\|continue-after-merge' tests/*.bats`:
  `tests/git_hook_pre_commit.bats` (20 passed), `tests/resolve_merge_local.bats`
  (4 passed), `tests/resolve_merge_briefing.bats` (8 passed),
  `tests/resolve_merge_remote.bats` (3 passed) — all 0 failed.

No regressions anywhere.

## Lint

`shellcheck -x scripts/resolve.sh` and
`shellcheck -x tests/resolve_compose.bats`: both clean.
