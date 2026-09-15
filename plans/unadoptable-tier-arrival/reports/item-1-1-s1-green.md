# Item 1.1 slice 1 — GREEN

## Commit

`7f143cf9cef6481d5f8c91f821aa8163bade856a` — "Item 1.1/1 — a dirty carrier with
a problem aborts the memory commit" (gitmoji-rewritten from `feat:`). Paths:
`scripts/lib/index-compose.sh`, `scripts/lib/resolve.sh`,
`tests/commit_memory.bats`. Nothing under `.claude/` or `plans/` staged.

## Implementation, one test at a time

Only one test batch was in scope (both `CLAUDECODE` and non-`CLAUDECODE`
assertions live in a single `@test`), so growth was:

1. **`gitlore_compose_problems_in`** (`scripts/lib/index-compose.sh`): real body
   replacing the RED stub — reads stdin with `|| [ -n "$line" ]`, compares each
   line against the literal `"$file: "` prefix with a quoted `case` pattern (no
   regex/grep), prints matches, returns 0 iff at least one matched.
2. **The rc 1 arm** (`gitlore_sync_memory_to_live`, `scripts/lib/resolve.sh`):
   first pass computed `dirty_problems` with a bare `x=$(...)` and the test
   still failed — `[ "$status" -eq 1 ]` passed but the duplicate-pointer
   substring assertion (line 162) did not. A standalone repro (outside bats,
   `BATS_TEST_DIRNAME` set by hand, sourcing the same helpers) showed the whole
   function returning silently: `gitlore_compose_problems_in` legitimately
   returns 1 on the "no match" case (a clean root index has none), and a bare
   command-substitution assignment aborts the enclosing function under this
   file's `set -euo pipefail`-inheriting callers the moment that happens
   (SC2310) — before any message prints. Fixed by wrapping every such call in
   `if cmd >/dev/null; then abort=1; fi`, the same pattern
   `gitlore_compose_check_pins`'s own caller already uses a few lines above.
   After that fix the target test passed outright; no second implementation
   attempt was needed beyond the SC2310 fix.

Both arms of `gitlore_say_for_agent_or_user` get the abort message (agent arm:
"the commit was aborted because a problem is in an index file this commit
changes … Fix it by editing the named lines, then retry; the summary needs
approval again."; user arm ends "Open this project in Claude Code and ask it to
repair the memory store, then retry." — same ending as the rc 2 arm). Both run
`touch "$msgfile"` and `return 1`. The advisory (report-only) branch is
otherwise untouched, byte-for-byte the same text as before.

## Tests

- `scripts/run-bats.sh tests/commit_memory.bats` — **29 passed, 0 failed**
  (whole file).
- `scripts/run-bats.sh tests/git_hook_pre_commit.bats` —
  **19 passed, 0 failed**.
- `scripts/run-bats.sh tests/index_compose.bats` — **65 passed, 0 failed**.
- `scripts/run-bats.sh tests/merge_memory.bats` — **23 passed, 0 failed**.
- `shellcheck scripts/lib/resolve.sh scripts/lib/index-compose.sh` — clean, no
  output.

No `just lint`/`just precommit` run — out of scope per the dispatch constraints
(orchestrator owns the full gate at phase boundaries).

## Notes

No precommit warnings to carry (precommit was not run, per constraints).
