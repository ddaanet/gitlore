# Item 1.1 slice 3 — GREEN report

Mode: GREEN. Commit: `956e4e3` "Item 1.1/3 — The compose return code decides" (3
files changed: `scripts/lib/resolve.sh`, `tests/commit_memory.bats`,
`tests/index_compose.bats`).

## Implementation

`gitlore_sync_memory_to_live` (`scripts/lib/resolve.sh:917`) replaced
`gitlore_compose "$mempath" >/dev/null || true` with a `case` over
`gitlore_compose`'s captured status and output:

- rc 0 — silent, as before.
- rc 1 — `gitlore_say_for_agent_or_user`, redirected to stderr, header
  `gitlore: tier composition refused — the memory indexes were left untouched:`
  followed by `gitlore_compose`'s forwarded problem lines, then a remedy
  sentence (differing between the agent and user arms). Falls through — the
  commit proceeds.
- rc 2 — same helper/redirect, header
  `gitlore: tier composition could not write an index — the memory indexes are only partly composed:`
  followed by the forwarded problem line, then a remedy sentence. Returns 1
  immediately, before `gitlore_sync_tiers_to_live` and before `$msgfile` is
  touched, so the approved summary survives for the retry.

Both header sentences are verbatim from `gitlore_compose_and_report`
(`scripts/lib/index-compose.sh:779,787`) as directed; the remedy sentences were
written fresh for this call site's register, not copied from that function's
`PostToolBatch`-JSON `ctx` text.

## Tests made green, one at a time

`scripts/run-bats.sh tests/commit_memory.bats -f "an off-pin compose refusal"`
then `-f "a compose write failure aborts"` — both passed individually before the
full-file run. Full run: `bats: 13 passed, 0 failed`.

## Regression suite

- `tests/git_hook_pre_commit.bats`, `tests/index_compose.bats`,
  `tests/integration_gitlink_staging.bats` run together:
  `bats: 83 passed, 0 failed`.
- `shellcheck -s bash scripts/lib/resolve.sh`: exit 0, no findings.

## Gate verdicts (read from sentinels, not the background notification)

The `just precommit` background run's completion notification never arrived in
this subagent (expected per the runbook note); verdict read instead from
`.git/gitlore/gates/`, each checked to postdate `scripts/lib/resolve.sh`'s edit
(mtime 16:49:10):

- `check-distribution` 16:51:00 — pass
- `lint` 16:52:41 — pass
- `test-unit` 16:58:30 — pass
- `test-integration` 16:58:30 — pass

All four postdate the gated input; team lead independently confirmed the same
before instructing the commit.

## Tree state after commit

`git status --porcelain` clean for everything under `scripts/`, `tests/`,
`plans/index-edit-propagation/` except the still-untracked
`plans/index-edit-propagation/reports/item-1-1-s3-test-review.md`, which was
already untracked before this dispatch started and is out of this slice's scope.
(The RED dispatch's own report,
`plans/index-edit-propagation/reports/item-1-1-s3-red.md`, was already committed
at `ca41cbe` and is not part of this diff.) A handful of unrelated untracked
dotfiles/dirs at the repo root (`.bashrc`, `.claude/agents`, `.mcp.json`, etc.)
predate this dispatch and were left untouched.

## Scope

Only `scripts/lib/resolve.sh`'s compose call site and its comment changed in
`scripts/`. Both test files rode the commit unchanged from the RED/review
dispatches — no edits made to make a case pass.
