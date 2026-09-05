# Recall artifact — index-edit propagation

Memory entries selected at the `/runbook` implementation-recall checkpoint, with
what each one is load-bearing for. Planning-relevant only; execution detail
reaches executors through dispatch prompts.

- `memory/ddaanet/hook-input-schema.md` — `agent_id` is present only when the
  hook fires from within a subagent, while `agent_type` also appears on the main
  thread of an `--agent` session. This is the whole basis of Phase 2's keying,
  and of "absent on the main thread, so nothing migrates". Also fixes
  `PostToolBatch` as per-batch, not per-turn, which is what bounds how long a
  baseline lives.
- `memory/ddaanet/hook-output-channels.md` — §2 for the channel mechanics
  (`systemMessage` is the user's, `additionalContext` the model's, stdout parses
  on exit 0 only, so a failure path reports and exits 0); §6 for the measured
  91%-vs-35% re-verification rate that settles Phase 3's "in addition to, not
  instead of". The file is large; §2 and §6 are the sections that matter here.
- `memory/ddaanet/genuine-red-not-missing-sut.md` — red is a failed assertion,
  never a missing symbol. Phase 1's SUT already exists, so its red is the
  committed carrier reading `stale hook`; Phase 2's and Phase 3's helpers are
  new, so their slice 1 needs the inert-stub shape rather than a bare "function
  not found".
- `memory/ddaanet/green-is-not-evidence.md` — the vacuous-negative shapes. Phase
  1 slice 2 pairs a SHA equality with a content assertion for this reason, and
  Phase 3 slice 4 carries an explicit negative so the SessionStart drain case
  cannot go vacuous.
- `memory/ddaanet/git-hook-env-leak.md` — the commit path stages inside a hook,
  so `GIT_INDEX_FILE` must survive the blanket unset, and a standalone hook run
  exercises none of it. `tests/git_hook_pre_commit.bats:149,185` and
  `tests/integration_gitlink_staging.bats` already lock this in; Phase 1 adds to
  those suites and must not regress the ordering they protect.
- `memory/ddaanet/design-doc-writing.md` — selected at the post-explore gate,
  once `scripts/check-docs-links.py` surfaced. Its §"Splitting an oversized
  subsystem" is what grounds Item 4.2's default: splitting raises total bytes
  and pays only where the moved material is self-contained, and a near-1:1 ratio
  means the material was never separable.

Post-explore recall gate: exploration surfaced the docs-hygiene checker
(`scripts/check-docs-links.py`) and the bats tier fixtures. The first added
`design-doc-writing` above. The second added nothing —
`test-the-invocation-path` is adjacent (hooks.json registration) and
`tests/cc_hook_index_compose.bats:45` already asserts it for the compose hook.
