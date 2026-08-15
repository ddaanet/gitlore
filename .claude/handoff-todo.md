## Open decisions

- Approve or reject the six changes proposed for `sandbox-effects`, listed in
  full under entry 2 of `plans/ddaanet-memory-review.md`: route the
  read-only-inspection standing default to the `prohibitions` plugin rather
  than to `shared-claude.md`; change the `apply-seccomp:
  unshare(CLONE_NEWUSER)` remedy from retry-unsandboxed to retry-once-
  unchanged; demote the strict-sandbox-mode section and state
  unsandboxed-fallback plus auto mode as the baseline; replace the claim that
  `Edit` may write `.claude/settings.json` with the built-in `update-config`
  skill; name backtick-bang expansion as the mechanism behind the sandboxed
  slash-command `## Context` block; and merge the `/add-dir` section into
  `classifier-denied-self-config`, carrying the *external repo outside the
  trusted source control org* verdict string and the ask-rules-are-not-
  authorization residue with it.
- Approve or reject the structure section proposed for `memory-writing` under
  entry 1b — five rules for organising a reference file that holds many
  independent facts under one trigger, drawn from what is wrong with
  `sandbox-effects`: order by the literal the reader arrives holding, one
  section per symptom with a discriminator rather than one per case, a shared
  remedy discussed once, a lead symptom-to-section map past roughly a screen
  of sections, and a cost-of-the-remedy fact filed under the remedy.
- Whether the guide-shaped facts become gitlore skills instead of memories.
  Deferred by agreement until the pass ends, because `memory-writing`,
  `index-compaction-triggers`, `design-doc-writing` and `green-is-not-evidence`
  all raise the same question and it is one decision rather than four.
- Whether to report the `unsandbox-git-status` scope finding to that repo as a
  brief. Its hook returns permissionDecision allow together with an
  `updatedInput` that carries the whole `tool_input` through, so any command
  holding a matching segment runs unsandboxed *and* pre-approved. Two live
  confirmations this session: a compound whose first segment was `true`, and a
  `handoff-checkpoint` call whose only match was the literal phrase appearing
  inside its JSON payload rather than as a command at all. The repo is outside
  this session's consent scope, so the brief needs an explicit go-ahead.

## Remaining

- Take the `sandbox.excludedCommands` reading. `~/.claude/settings.json` now
  carries `"ls -d /Users/david/.claude/ide"` beside the pre-existing entry;
  the six probes and how to read each are in the entry-2 section of the
  ledger. Four semantics are possible — whole-command, any-segment,
  all-segments, and per-`exec` override — and which one holds decides whether
  `git` can be excluded outright, whether a `prohibitions` hook is needed at
  all, and whether excluding a bare command name is safe. Remove the probe
  entry from the settings file once the reading is taken.
- Review the remaining 98 ddaanet memories, continuing down the index-line size
  order recorded in the ledger's table. Entry 3 is `green-is-not-evidence` at
  690 B, then `index-compaction-triggers` at 590 B.
- Apply every approved edit in one pass at the end, then re-check the index
  against Claude Code's 24.4 KB loader cap. It stands at 26,219 B across 101
  lines, so the tail entries do not reach a session today.
