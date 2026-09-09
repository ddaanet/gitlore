# Item 3.1, slice 3 — GREEN report

Scope: `scripts/cc-hooks/session-start.sh` only. `tests/cc_hook_session_start.bats`
untouched. Nothing committed, tree left dirty and unstaged.

## What made case 1 pass

Added a fold immediately before the final `emit_session_json` (now at the bottom
of the file), between the tier-guidance `protocol_ctx` append and the emit
comment:

```bash
gitlore_relay_drain "$mempath"
if [ -n "$GITLORE_RELAY_SYSMSG" ]; then
  add_sysmsg "$GITLORE_RELAY_SYSMSG"
  protocol_ctx="$protocol_ctx

$GITLORE_RELAY_CTX"
fi
```

`gitlore_relay_drain` (already sourced via `index-sync.sh`) enumerates every
keyed marker under the memory gitdir, folds each into `GITLORE_RELAY_SYSMSG` /
`GITLORE_RELAY_CTX` framed as `--- gitlore-relay agent <id> ---\n<block>\n`, and
removes the marker file — same helper the two PostToolBatch hooks already
drain (`2df5283`). `add_sysmsg` puts the relayed sysmsg body on the user-facing
channel with the accumulator's existing blank-line join; `protocol_ctx` gets
the ctx body appended the same way every other section in this file appends to
it. Both channels get the framing line and the body, satisfying all four
content/framing assertions (`:373-376`), and `gitlore_relay_drain`'s own
`rm -f "$marker"` satisfies the marker-removal assertion (`:379` in the test
file).

## Case 2 still passes, and why the fold cannot emit framing on a marker-less session

`gitlore_relay_drain` always sets `GITLORE_RELAY_SYSMSG=""` / `GITLORE_RELAY_CTX=""`
first and returns 0 with both empty when it finds no marker (`find` yields
nothing, `[ -n "$names" ] || return 0`). The fold's own `[ -n "$GITLORE_RELAY_SYSMSG" ]`
guard is then false, so neither `add_sysmsg` nor the `protocol_ctx` append runs at
all — no framing line, no blank paragraph, on either channel. That guard is the
fix for mutation M1a from the test-review report: without it, `add_sysmsg ""`
and an unguarded `protocol_ctx` join would still pass case 2 (the negative watches
the framing literal, not blank-line pollution) but would append a trailing empty
paragraph to both channels on every ordinary, marker-less session — which is
every session this hook has ever run in the test suite. Guarding on
`[ -n "$GITLORE_RELAY_SYSMSG" ]` matches the shape both committed PostToolBatch
folds use (`index-compose.sh`, `74dac38`).

Ran `bats -f "session-start with no marker emits no relay framing"` in isolation
to confirm: `ok 1`.

## Fold placement relative to the three emit sites

Three `emit_session_json` call sites in the file, unchanged in number and
position:

1. `:202` (pristine numbering) — diverged branch, early exit.
2. `:207` (pristine numbering) — fast-forward-failure branch, early exit.
3. the final emit at the bottom of the file (now shifted down by the fold's 16
   inserted lines) — the only one reached on a clean or dirty-but-mergeable
   store.

The fold sits immediately before call site 3 and nowhere near sites 1 or 2 — it
runs after the entire `gitlore_memory_dirty` if/elif/else block, after root-index
repair, after the tier loop, and after tier-guidance composition, so by
construction it cannot execute before either early exit. This is the design
call from the dispatch: on the two early exits the store is in a state the user
must repair with `/gitlore:resolve`, so draining there would surface a
subagent's relayed report in the middle of a divergence notice the user is
trying to act on. The marker survives undrained to the session after the
repair — delayed, never lost, which is what "SessionStart is the backstop"
means. A comment at the fold site states this explicitly (see the code below).

## The `-n` guard is not nested inside `[ -n "$sysmsg" ]`

Per the M8 finding in the test-review report: today every reachable path
through the four `gitlore_memory_dirty` branches calls `add_sysmsg`
unconditionally before falling through, so `$sysmsg` is never empty by the time
the final emit site is reached — measured at 52/52 non-empty across ten
suites. Nesting the fold inside `[ -n "$sysmsg" ]` would therefore be
behaviour-identical to the implementation above on every fixture in the repo
today, and neither test case can tell the two apart. The implementation guards
only on `$GITLORE_RELAY_SYSMSG`, matching the two committed PostToolBatch folds,
and carries this comment at the fold site:

```
# Guarded on $GITLORE_RELAY_SYSMSG, deliberately NOT nested inside
# `[ -n "$sysmsg" ]`: every dirty branch above calls add_sysmsg
# unconditionally, so $sysmsg is never empty by the time we reach here today —
# but that is an accident of the branches above, not a contract this fold may
# lean on. Conditioning on it would be behaviour-identical now and would
# silently drop the relay the day one of those branches stops reporting.
```

## Checks that passed, by name

- `scripts/run-bats.sh tests/cc_hook_session_start.bats` — 23 passed, 0 failed.
- `scripts/run-bats.sh tests/cc_hook_worktree_remove.bats tests/merge_memory.bats tests/push_rejection_discriminator.bats tests/tier_discovery.bats tests/tier_divergence.bats` — 81 passed, 0 failed.
- `shellcheck -s bash scripts/cc-hooks/session-start.sh` — clean.
- `scripts/lint-shell.sh` — 137 files clean.
