## Open decisions

- Approve or reject the gitlore-skills conversion proposed in entry 4b of the
  ledger: `memory-writing` and `index-compaction-triggers` become skills rather
  than edited memories, with short purpose-first descriptions and hook-fired
  triggers (a write under `memory/`; the budget check gitlore already runs).
  Long descriptions make it a lateral move, since skill descriptions load every
  session exactly as index lines do. Approving supersedes the A/B re-split
  proposed in entry 4, and resolves entries 1, 3 and `design-doc-writing` to
  verdict plugin at the same time.
- Entry 3, `green-is-not-evidence`: cut the closing sentence beginning *It pairs
  with the sibling lesson* — it has named no target since before the merge that
  created the file — or resolve it to `[[spec-enumerations-need-rederiving]]`.
- Entry 3: rewrite the index line from diagnoses to arrivals at roughly
  unchanged size, so it carries what a session holds on arrival rather than
  labels recognisable only after reading. Nine body additions are absent from
  it.
- Approve or reject the six changes proposed for `sandbox-effects`, set out in
  full under entry 2 in `plans/ddaanet-memory-review-2a-exclusion-mechanism.md`
  and `-2c-deny-and-decisions.md`: route the read-only-inspection standing
  default to the `prohibitions` plugin rather than to `shared-claude.md`; change
  the `apply-seccomp: unshare(CLONE_NEWUSER)` remedy from retry-unsandboxed to
  retry-once-unchanged; demote the strict-sandbox-mode section and state
  unsandboxed-fallback plus auto mode as the baseline; replace the claim that
  `Edit` may write `.claude/settings.json` with the built-in `update-config`
  skill; name backtick-bang expansion as the mechanism behind the sandboxed
  slash-command `## Context` block; and merge the `/add-dir` section into
  `classifier-denied-self-config`, carrying the external-repo-outside-the-
  trusted-source-control-org verdict string and the
  ask-rules-are-not-authorization residue with it.
- Approve or reject the structure section proposed for `memory-writing` under
  entry 1b — five rules for organising a reference file that holds many
  independent facts under one trigger.
- How the `git:*` exclusion actually gets written. `excludedCommands` is
  user-scope `~/.claude/settings.json`, which the classifier denies to the
  agent; the route is the built-in `update-config` skill or the `/sandbox`
  menu. `find:*`, `ls:*` and `claude:*` were agreed alongside it.
- Whether to carry the `cwd-safety` relaxation to `/Users/david/code/cwd-safety`
  and how — it is outside this session's consent scope, so it needs an explicit
  go-ahead or a brief. The shape is settled: rules 3, 1 and 5c stop blocking and
  stop rewriting, rule 4 is unchanged, and its message must name
  `cd <root> && <cmd>` explicitly.
- Whether to report the `unsandbox-git-status` findings to that repo as a brief
  — the `permissionDecision: allow` scope hole, and its retirement once
  exclusions are in and verified. Same consent-scope constraint.

## Remaining

- Review the remaining 96 ddaanet memories, continuing down the index-line size
  order recorded in the ledger's table.
- Apply every approved edit in one pass at the end of the review.
- Carry the !`cmd` findings in
  `plans/ddaanet-memory-review-2d-corpus-scrape.md` into memory when that pass
  runs: expansion is sandboxed by default, `excludedCommands` applies to it,
  PreToolUse hooks do not fire on that path, and `mLe` runs the extracted blocks
  concurrently under `Promise.all`.
- Resolve or record the open anomaly in 2d: one unsandboxed !`cmd` run returned
  the full phantom-mask listing, and three later runs were clean. Neither the
  concurrent `Promise.all` sibling nor a long-lived sandboxed background task
  reproduced it. It decides whether an exclusion delivers clean output always or
  only usually.
- Compact the memory index, unless entry 4b lands and moots it — the store sits
  over Claude Code's 24.4 KB loader cap, so the tail entries do not reach a
  session.