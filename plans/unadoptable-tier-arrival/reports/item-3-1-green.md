# Item 3.1 — GREEN report

Commit: a59061f — "🐛 Item 3.1/1-5 — a merged index that fails the check does
not land" (files: `scripts/resolve.sh`, `tests/resolve_compose.bats`; no other
paths staged).

## What changed

`scripts/resolve.sh` `compose_merged_indexes`: right after
`composed=$(gitlore_compose_up "$memroot" "$merged_tier") || rc=$?`, on
`rc -eq 1` the merged index path is picked (`$memroot/$merged_tier/MEMORY.md`
for a tier merge, `$memroot/MEMORY.md` for a memory-root merge) and filtered
through `gitlore_compose_problems_in <<<"$composed"`. A match prints
`gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:`
plus the problem lines (`gitlore:   ` prefix, matching the file's existing
arms), then `return 1` — before any `add`, so under the caller's bare call and
`set -e` this aborts `continue-after-merge` with merge state and `MERGE_HEAD`
kept. No match falls through to the unchanged `rc` dispatch (tier-unadopted,
write-failure, uncomposed-commit arms), so `rc -eq 2` and any non-`rc-1` problem
still land uncomposed as before.

Idiom: plain `echo`/`printf … >&2`, matching every other arm in this function
(none of which use `gitlore_say_for_agent_or_user`, unlike other arms elsewhere
in the same file).

Header comment: the "A refusal never blocks the merge" paragraph (former
`scripts/resolve.sh:85-90`) is rewritten to state which refusals block (a
problem attributed to the merged index) and which still land uncomposed
(everything else), present tense, no plan/item citations. The function's
"Returns 0." line is corrected to document the new `return 1` path and when it
fires.

## Test order (all via `scripts/run-bats.sh tests/resolve_compose.bats --filter '<name>'`)

1. Slice 1, "a tier merge whose merged carrier has a duplicate pointer is not
   committed" — pass.
2. Slice 1, "a head-vs-live tier merge whose merged carrier has a duplicate
   pointer is not committed" — pass.
3. Slice 4, "a duplicate in the merged root index keeps the merge unlanded" —
   pass.
4. Slice 4, "a memory-root merge whose merged index welds a line is not
   committed" — pass.
5. Guard, slice 2, "a kept refused merge re-emits the continuation directive" —
   pass (unchanged).
6. Guard, slice 3, "a fixed merged carrier lands" — pass (unchanged).
7. Guard, slice 5, "a memory-root merge with only a leftover root prefix commits
   uncomposed" — pass (unchanged).

## Suite results

- `tests/resolve_compose.bats`: 15 passed, 0 failed.
- `tests/tier_divergence.bats`: 19 passed, 0 failed.
- `tests/merge_memory.bats`: 35 passed, 0 failed.
- `tests/git_hook_pre_commit.bats`: 20 passed, 0 failed.
- `tests/pre_push_hook.bats`: 9 passed, 0 failed.
- `tests/resolve.bats`: 8 passed, 0 failed.
- `tests/resolve_merge_local.bats`: 4 passed, 0 failed.
- `tests/resolve_recovery.bats`: 23 passed, 0 failed.
- `tests/resolve_merge_briefing.bats`: 8 passed, 0 failed.
- `tests/resolve_merge_remote.bats`: 3 passed, 0 failed.

(The last seven found by
`grep -rl "continue-after-merge\|compose_merged_indexes" tests/*.bats` beyond
the three named in the dispatch; `tests/merge_memory.bats` itself has no literal
match for that grep but was run as directed.)

`shellcheck scripts/resolve.sh` — clean. `shellcheck tests/resolve_compose.bats`
— clean.
