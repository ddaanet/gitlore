# Item 1.1 slice 1 — GREEN

Commit: `f6ef928efa1233cac43b895ed4ffbc711123c3b7`
`✨ Item 1.1/1 — External contract — the committed carrier is the composed one`

## Implementation

`scripts/lib/resolve.sh`, inside `gitlore_sync_memory_to_live`'s `dirty = 1`
branch, after the freshness check and before `gitlore_sync_tiers_to_live`:

```sh
    # Compose before the tier commit below: composition writes carrier files
    # inside the tiers, so it must land before gitlore_sync_tiers_to_live moves
    # their gitlinks, or the gitlink pins the pre-compose content — the same
    # one-behind lag the tier-first ordering already exists to prevent. Return-
    # code handling and reporting on refusal/failure are not yet wired here.
    gitlore_compose "$mempath" >/dev/null || true
```

**The `|| true` is a slice 1 placeholder, not a defect.** It swallows all three
of `gitlore_compose`'s return codes (0 success, 1 refused, 2 write failure)
uniformly. Slice 3 replaces this with a `case` over the return code — rc 1
reported via `gitlore_say_for_agent_or_user` and the commit allowed to proceed,
rc 2 reported and the commit aborted. Slice 1's two tests only exercise the rc-0
path (a store `gitlore_compose` does not refuse), so no rc-handling is
observable yet; adding it now would be scope creep the dispatch explicitly named
as out. Flagging this here so code review does not read the bare `|| true` as an
oversight.

## Tests made green

Both new cases, from already-written, already-failing test files:

- `tests/commit_memory.bats`: "commit-memory composes the carrier into the
  commit it makes"
- `tests/git_hook_pre_commit.bats`: "the parent pre-commit hook composes the
  carrier before committing"

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats` →
`bats: 24 passed, 0 failed`. No pre-existing case regressed (was 9/10 and 13/14
red; now 10/10 and 14/14).

## Precommit gate

`just precommit` was launched with `run_in_background: true` per the runbook's
instruction, but its completion notification never arrived in this session — the
orchestrator (team lead) reported from its own vantage in the same repository
that the run had already finished and passed, and pointed at the recorded
evidence rather than a notification:

- no `just`/`bats`/`shellcheck` process running
- gate sentinels under `.git/gitlore/gates/`: `lint` 14:09, `test-unit` 14:17,
  `test-integration` 14:19, `check-distribution` 14:08
- last edit to any gated input (`scripts/lib/resolve.sh` 14:06,
  `tests/commit_memory.bats` 13:43, `tests/git_hook_pre_commit.bats` 13:50)
  predates all four sentinels, so the recorded passes cover the tree as
  committed.

The gate verdict here is read from those sentinels, not from a completion
notification landing in this session. Before committing, the two new cases were
re-run directly (`scripts/run-bats.sh` on the two files, 24/24 passed) as an
independent, in-session confirmation.

`just format-docs` (precommit's first step) rewrapped
`plans/index-edit-propagation/reports/item-1-1-s1-red.md` and
`item-1-1-s1-test-review.md` — both already tracked from a prior commit. That
rewrap is included in this slice's commit per the orchestrator's instruction,
since it is a mechanical side effect of the gate run on files this session's
precommit touched, not new content.

## Commit hygiene

Staged and committed only: `scripts/lib/resolve.sh`, `tests/commit_memory.bats`,
`tests/git_hook_pre_commit.bats`, and the two reformatted report files above —
via `git commit -- <paths>`, not `git commit -a` or `git add -A`. The
orchestrator's own staged files (`.claude/handoff-task.md`,
`.claude/handoff-todo.md`) were left staged and untouched; `git status --short`
after the commit shows only those two `M ` entries remaining. No `--no-verify`;
the hook ran normally on this commit.

## Out of scope, confirmed untouched

Slice 2's dirty-only guard, slice 3's rc-`case` and message texts, every
pre-existing case in both suites, Phase 2/3/4 files, `docs/`.
