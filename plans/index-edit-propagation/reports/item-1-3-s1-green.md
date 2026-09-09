# Item 1.3, slice 1 — GREEN

Target: `gitlore_recover_landed_merge` (`scripts/lib/resolve.sh`), both rc-0
branches. New helper `gitlore_stage_recovered_gitlink`, placed after its caller
per the entry-points-first convention. Nothing under `tests/` touched.

## Implementation

```sh
gitlore_stage_recovered_gitlink() {
  local store="$1" abs="$2"
  local super rel own_path
  super=$(git -C "$store" rev-parse --show-superproject-working-tree) || super=""
  [ -n "$super" ] || return 0
  [ -f "$super/MEMORY.md" ] || return 0
  rel="${abs#"$super"/}"
  own_path=$(git config --file "$super/.gitmodules" \
    "submodule.${GITLORE_SUBMODULE_NAME}.path") || own_path=""
  [ "$rel" != "$own_path" ] || return 0
  # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
  gitlore_git -C "$super" add -- "$rel" \
    || printf 'gitlore: %s could not be staged in %s. Run `git -C %s add -- %s` before the next session, or the pointer will be reset to its previous commit.\n' \
      "$rel" "$super" "$super" "$rel" >&2
}
```

Called from both `gitlore_recover_landed_merge` rc-0 branches, each right after
`gitlore_drop_merge_preparation "$store"` and before the branch's own message —
so in the HEAD-moves branch it runs strictly after the
`checkout -q --detach "$landed"` that restores HEAD (M2e's ordering constraint),
and it fires identically in the HEAD-already-carries branch (M2c's
branch-coverage constraint).

## The predicate, clause by clause

1. **`super=$(git -C "$store" rev-parse --show-superproject-working-tree)`,
   empty → return 0.** No superproject, nothing to stage — a store with no
   enclosing repo (e.g. run against a bare clone in isolation) cannot be a tier.
2. **`[ -f "$super/MEMORY.md" ]`.** The idiom at `scripts/lib/util.sh:185` and
   `scripts/lib/index-compose.sh:211`. Unpinned by any case (M1a ships green
   across all twenty in the test review's matrix) and kept as defence in depth:
   the state it would exclude — a store enclosed by a project that is not a
   memory store at all — is unreachable through
   `gitlore_guard_stale_merge_state`'s callers, which walk
   `gitlore_memory_stores` alone, so no fixture can reach the guard from outside
   a memory tree in the first place. Said in the comment rather than implied as
   covered.
3. **`rel="${abs#"$super"/}"` then `[ "$rel" != "$own_path" ]`, where `own_path`
   reads `submodule.${GITLORE_SUBMODULE_NAME}.path` from `$super/.gitmodules`
   via `git config --file`.** This is the clause that does the work.
   `--show-superproject-working-tree` alone cannot discriminate a tier's
   superproject (the memory root) from the memory root's own superproject (the
   user's project) — both are non-empty, and the memory root itself is a real
   submodule, so a naive "non-empty → stage" stages the memory root's own
   gitlink into the user's project index, outside every approval gate (M1's
   proof, case 3). The third clause is what excludes exactly that: the memory
   root's own relative path (`memory`) equals the user's project's own
   `submodule.gitlore-memory.path`, so it is skipped, while a tier's relative
   path (e.g. `ddaanet`) is never registered under that key in the memory root's
   own `.gitmodules` (the memory root registers tiers under their own names, not
   under `gitlore-memory`), so `own_path` comes back empty or unequal and the
   tier is staged.

   Read via `git config --file "$super/.gitmodules" …` rather than
   `gitlore_memory_path` (`scripts/lib/util.sh:83`) deliberately: that helper
   reads the *current working directory's* `.gitmodules`, and
   `gitlore_guard_stale_merge_state` (and this helper through it) runs from
   whatever cwd the caller happens to be in — case 6 in the test file calls it
   from `$BATS_TEST_TMPDIR`, a cwd outside the superproject entirely, to pin
   exactly this (M3 in the test review's matrix).

   No `2>/dev/null` on the `git config --file` call: per the existing comment at
   `scripts/lib/util.sh:87-88`, `git config --file` is silent on a missing file
   or a missing key (rc=1, no stderr), so nothing here is suppressed that
   shouldn't be.

**No membership test against `gitlore_tier_paths "$super"`.** Per the dispatch's
explicit instruction and the test review's finding (§4): a store has a
superproject only where that repo registers it as a submodule, so such a test
would restate what `--show-superproject-working-tree` already settled — the
review measured that dropping it (M1b) moves no case across all twenty.

## Other constraints from the mutation matrix

- **Named-path staging only** (`add -- "$rel"`, never `add -A`) — an over-broad
  stage would sweep an unapproved worktree edit (e.g. a stray `SCRATCH.md`) into
  the enclosing store's index for the next approved commit to carry. Verified by
  case 1's negative assertion.
- **Staging targets the superproject**, not any further ancestor —
  `gitlore_git -C "$super" add`.
- **Fires on both rc-0 branches** — the call sits in each branch identically.
- **Best-effort and non-fatal**: the `add` failure is caught in `||` and only
  emits a `printf … >&2`; the function still returns 0 (nothing in its body
  returns non-zero after that point), so the caller's own `return 0` stands.
  Matches `gitlore_adopt_tier_into_root`'s precedent wording style, plain
  `printf`, not `gitlore_say_for_agent_or_user` — the test asserts the literal
  phrase `could not be staged`, present verbatim in the message.

## Suite results

`scripts/run-bats.sh --jobs 1 tests/resolve_recovery.bats`, `CLAUDECODE=1`:

- Before: 16 passed, 4 failed (cases 13/14/16/17 red, matching the
  RED/test-review reports; 15 and 18 born-green).
- After: **20 passed, 0 failed.**

Adjacent suites, `CLAUDECODE=1`, before and after are identical since nothing in
`scripts/` changed except this file and it is additive/newly-called-only —
`scripts/run-bats.sh --jobs 1 tests/resolve.bats tests/tier_divergence.bats tests/commit_memory.bats tests/index_compose.bats`:
**109 passed, 0 failed**, both before this change (unchanged code) and after.

## Three `CLAUDECODE` worlds, `tests/resolve_recovery.bats`

| world | result |
| --- | --- |
| `CLAUDECODE=1` | 20 passed, 0 failed |
| `env -u CLAUDECODE` | 20 passed, 0 failed |
| `env CLAUDECODE=0` | 20 passed, 0 failed |

Identical across all three, as expected — the staging path never reads
`gitlore_say_for_agent_or_user`'s agent/user split; the failure report is a
plain `printf … >&2`.

## `shellcheck`

`shellcheck scripts/lib/resolve.sh` — clean.

## Tree state

`git diff --stat tests/` — `tests/resolve_recovery.bats | 198 ++++...`, 198
insertions, identical to what this dispatch inherited (the RED/test-review
dispatches' work; nothing added or changed here). No file under `tests/`
modified by this dispatch. `git status --short` shows only
`scripts/lib/resolve.sh` modified (this change) plus the pre-existing dirty
`plans/index-edit-propagation/runbook.md` and the two untracked prior reports.
Nothing staged, nothing committed.
