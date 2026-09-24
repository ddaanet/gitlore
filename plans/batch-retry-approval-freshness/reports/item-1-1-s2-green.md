# Item 1.1, slice 2 — GREEN report

`scripts/cc-hooks/memory-commit-batch.sh` only, per the dispatch contract.

## Diff summary

- The success-path invocation drops `-F "$msgfile"`: `commit-memory.sh` now
  runs bare, so its own freshness judgment on the approval already on disk is
  the gate (D16, item 1.1/1, already landed).
- The failure branch reads `fresh=$(gitlore_commit_msg_freshness "$mempath")`
  after the run. `yes` keeps the existing deferred `emit` (systemMessage +
  `additionalContext` mentioning `retries by itself`) unchanged. Otherwise it
  emits the re-approval pair: systemMessage exactly
  `gitlore: memory commit deferred — the approved summary no longer covers the store, approval needed again`;
  `additionalContext` built with `printf '%s\n\n%s\n'`, an acts-only paragraph
  naming `$msgfile` twice (present again, then write here) followed by
  `gitlore_memory_approval_clause` last. Neither `$out` nor the trigger file
  is named on this branch, and `$msgfile` is never touched — no `touch`,
  rewrite or removal.
- The comment block above the invocation is rewritten to state the current
  contract (bare invocation, freshness judged by the script, the hook's two
  failure messages chosen by freshness, both IPC files kept on every failure)
  rather than narrating the defect.

No other script or test edited.

## Green run

`bash scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats`:

```
bats: 12 passed, 0 failed
```

All 12, including the new `a fix after an aborting index does not commit
under the old approval` and the two pre-existing tests the dispatch named
(`a locked repo keeps both IPC files so the next batch retries transparently`,
`a refusal that needs a fix keeps both IPC files and hands the agent the
fix`).

## `just precommit` verdict

Ran in the foreground (the first foreground call exceeded the Bash tool's
600s cap and was moved to background automatically; polled the background
task's own output file to completion rather than reading `ps` or relying on a
notification, per the repo's background-gate convention). Exit code 0, every
check passed:

- `format-docs` — ran (rumdl reflow over `docs/` and `plans/`)
- `check-distribution` — cached (inputs unchanged)
- `check-memory-hygiene` — 67 facts, 162 files scanned, 0 in every blocking
  category (frontmatter, name-drift, first-person, direct-naming,
  pre-rename, broken-reference, volatile-state); 15 deictic and 6
  dangling-wikilink warnings, non-blocking
- `check-docs-links` — 55 decisions, 135 files scanned, 0 in every category
  (broken-link, unstubbed-decision, stub-without-body, duplicate-decision,
  duplicate-conclusion, undefined-decision, enumeration-drift,
  delegation-drift, oversized-file)
- `check-version` — in sync (0.8.0)
- `lint` — cached (inputs unchanged)
- `test-unit` — 94 suites run, 1020 passed, 0 failed
- `test-integration` — 10 suites run, 72 passed, 0 failed

## Commit

`16abc351408ee35fa5d0ffd9f10d73ffe4f7251a` — `fix: Item 1.1/2 — the batch
hook judges the retry by the approval's freshness` (gitmoji-prefixed 🐛 by the
commit-msg hook), `scripts/cc-hooks/memory-commit-batch.sh` and
`tests/cc_hook_memory_commit_batch.bats` together. `memory/` was clean, so the
parent pre-commit hook did not block.
