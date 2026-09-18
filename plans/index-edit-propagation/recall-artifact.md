# Recall artifact — index-edit propagation

Memory entries selected at the `/runbook` implementation-recall checkpoint, with
what each one is load-bearing for. Planning-relevant only; execution detail
reaches executors through dispatch prompts.

- `memory/ddaanet/hook-output-channels.md` — §2 for the channel mechanics
  (`systemMessage` is the user's, `additionalContext` the model's, stdout parses
  on exit 0 only, so a failure path reports and exits 0); §6 for the measured
  91%-vs-35% re-verification rate that settles Phase 3's "in addition to, not
  instead of". The file is large; §2 and §6 are the sections that matter here.
- `memory/ddaanet/git-hook-env-leak.md` — the commit path stages inside a hook,
  so `GIT_INDEX_FILE` must survive the blanket unset, and a standalone hook run
  exercises none of it. `tests/git_hook_pre_commit.bats:149,185` and
  `tests/integration_gitlink_staging.bats` already lock this in; Phase 1 adds to
  those suites and must not regress the ordering they protect.
Four of the entries this checkpoint selected are no longer memory files; their
content ships as skill material, which is where the reasoning above is
recoverable from:

- the hook stdin payload schema — `agent_id` only inside a subagent while
  `agent_type` also appears on the main thread of an `--agent` session, and
  `PostToolBatch` as per-batch rather than per-turn — is
  `plugin-craft:hook-authoring`'s reference material. It grounds Phase 2's
  keying, "absent on the main thread, so nothing migrates", and the bound on how
  long a baseline lives.
- red is a failed assertion, never a missing symbol, and the vacuous-green
  shapes are `craft:test-discipline`'s genuine-red, vacuous-green and
  non-vacuous-negatives nodes. Phase 1's SUT already exists, so its red is the
  committed carrier reading `stale hook`, while Phase 2's and Phase 3's helpers
  are new and their slice 1 needs the inert-stub shape; Phase 1 slice 2 pairs a
  SHA equality with a content assertion, and Phase 3 slice 4 carries an explicit
  negative so the SessionStart drain case cannot go vacuous.
- the six-section living design doc and its splitting rules are
  `craft:design-doc-writing`, whose splitting-an-oversized-doc node grounds Item
  4.2's default: splitting raises total bytes and pays only where the moved
  material is self-contained, and a near-1:1 ratio means it was never separable.

Post-explore recall gate: exploration surfaced the docs-hygiene checker
(`scripts/check-docs-links.py`) and the bats tier fixtures. The first added the
design-doc material above. The second added nothing — asserting the invocation
path (`craft:test-discipline`'s coverage-shape node) is adjacent (hooks.json
registration) and `tests/cc_hook_index_compose.bats:45` already asserts it for
the compose hook.
