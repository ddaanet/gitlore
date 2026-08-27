## Brief: `continue-after-merge` dies on a store with no root `MEMORY.md`, and the installer can create such a store

2026-08-27 — target: `gitlore` (this repo) · found from `prohibitions`

Confirmed on gitlore 0.5.0 (the installed plugin) and re-checked against
this repo's `HEAD`. `prohibitions`' `just release` push hit a real
`ddaanet` tier divergence (49 remote commits vs 2 local, one conflict).
The memory-merger synthesized and staged a correct resolution; the
approved continuation then printed one line and exited 128 before
committing anything:

```
fatal: pathspec 'MEMORY.md' did not match any files
```

### What happened

1. `scripts/resolve.sh` `compose_merged_indexes` ends with
   `gitlore_git -C "$memroot" add -- MEMORY.md` (line 136 at `HEAD`),
   unconditional, under `set -euo pipefail`. `gitlore_compose_up` just
   above it tolerates a missing root index (`[ -f "$root" ] || return 0`);
   the add does not. The script died there — before the tier commit, the
   gitlink staging, the state cleanup and both `live` pushes.
2. `prohibitions`' root memory store has never had a `MEMORY.md`: its "Initial
   memory" commit has an empty tree. `scripts/install/init-submodule.sh` seeds
   from the CC auto-memory dir when
   `[ -d "$src" ] && ! gitlore_is_migration_stub "$src"` — an **empty** `$src`
   satisfies that, so `cp -R` copies nothing and the `# Memory Index` scaffold
   branch is skipped. Every later gitlore path assumes the scaffold exists; this
   repo has been running with a mounted tier that could never compose into a
   root index.
3. After the failed continuation, the next memory gate's stale-merge guard
   (0.5.0 `lib/resolve.sh`, `stale-with-merge-head`) re-emitted the
   directive as `abort-then-retry`, which would have discarded the staged
   synthesis and reproduced the identical failure. The merger caught it.
   Source `HEAD` (`repair stale merge state … always continue a prepared
   merge`) already routes `stale-with-merge-head` to continue — this item
   is fixed but unreleased.

### Recovery used

Wrote the installer's scaffold to `prohibitions/memory/MEMORY.md` by hand
(`# Memory Index` / `(populated by Claude over time)`), then re-ran the
original `continue-after-merge` verbatim: exit 0, tier merge committed,
both `live` pushes landed, root store left with `A MEMORY.md` and the
moved gitlink staged for the next FR11 commit.

### Decisions to make here

- `init-submodule.sh`: treat an empty `$src` like an absent one — fall
  through to the scaffold. Copying nothing and skipping the scaffold is
  never the intent. Consider also `gitlore_mark_migrated` on an empty dir:
  it leaves a stub claiming a migration that moved nothing.
- `resolve.sh` `compose_merged_indexes`: either guard the add
  (`[ -f "$memroot/MEMORY.md" ] &&`) matching `gitlore_compose_up`'s own
  tolerance, or — better — have the continuation create the scaffold when
  the root index is missing and say so on stderr, since a store without
  one is already broken for composition. Either way the merge commit must
  not be blocked by a missing index.
- A SessionStart check that the root store has a `MEMORY.md` would have
  surfaced this on day one instead of at the first tier divergence; the
  existing stale-index warning ran every session here and never noticed
  the file it was reporting on did not exist (it was reporting on the
  tier's index).
- Cut a release carrying the `stale-with-merge-head → continue` fix; 0.5.0
  consumers still get `abort-then-retry`.

### Constraints

- Test the empty-`$src` installer path and the missing-root-index
  continuation path in the suite; both are one-fixture cases.
- `prohibitions` needs nothing further — its scaffold is in place and will
  land with its next memory commit.
