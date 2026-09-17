# Item 2.1 / Slice 2 — RED

New test in `tests/push_behind_vs_diverged.bats`: "a behind arm's repair
survives a later tier's failure", plus a local `decline_pushes_to` helper
(mirrors `tests/resolve_compose.bats:520-524`).

## Fixture

Tiers `aa` then `bb`, mounted with `mount_tier_at_live` and published as in
slice 1's shared setup (no `set_tier_manifest`/compose needed —
`gitlore_tier_paths` reads `.gitmodules`, which `mount_tier_at_live` already
registers).

- `aa`'s remote gets a duplicate-bullet fact via `push_tier_fact` (the :376
  arrival shape), so `aa` is behind; its own behind-arm take repairs it.
- `bb` is advanced past its own remote with `advance_tier_past_remote`, and its
  bare remote gets a `pre-receive` hook that declines every push for a reason
  other than divergence (`decline_pushes_to`).

## Run

`scripts/run-bats.sh tests/push_behind_vs_diverged.bats --filter "a behind arm's repair survives a later tier's failure"`

Against the current tree (post 50405f0, no in-arm retry):

```
not ok 1 a behind arm's repair survives a later tier's failure
# (in test file tests/push_behind_vs_diverged.bats, line 624)
#   `[ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$aa_live" ]' failed
```

Every earlier assertion passed before that failure, in order:
- `aa` was behind before the push (`aa_live_before != aa_fact`, and an ancestry
  check confirms it).
- `bb`'s remote push was refused by the hook and the run exited 1, with stderr
  containing `pushing tier 'bb' failed, and not because of divergence`.
- `aa`'s own take repaired it in-loop: stderr contains
  `gitlore: tier 'aa' — the repair is committed in its local 'live', and this push publishes it.`;
  the repair commit's sole parent is the fetched fact (`aa_fact`); its
  `MEMORY.md` carries the duplicate bullet exactly once.

Only the final assertion — `aa`'s remote `live` equals the repair commit —
fails: the repair is stuck in `aa`'s local `live` because `bb`'s failure returns
1 from the loop before the post-loop pass runs.

## Pre-change evidence

Scratch copy: `git archive 50405f0~1 | tar -x -C <scratch>` (the commit before
the retry was removed), with this test file copied in, run the same way. Result:
`1 passed, 0 failed` — the pre-change in-arm retry publishes `aa`'s repair
before `bb`'s push is attempted. Scratch directory removed afterward;
`git status --short tests/ scripts/` in the working tree came back clean apart
from the new test.

## shellcheck

`shellcheck -x tests/push_behind_vs_diverged.bats`: clean.
