## Open decisions

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
  `classifier-denied-self-config`, carrying the *external repo outside the
  trusted source control org* verdict string and the
  ask-rules-are-not-authorization residue with it. Change (d) has shrunk since
  it was written — the `UserPromptSubmit` warning hook it proposed is
  unnecessary, because `excludedCommands` is now confirmed to apply to the
  `` !`cmd` `` path, so (d) reduces to naming the mechanism.
- Approve or reject the structure section proposed for `memory-writing` under
  entry 1b in the ledger hub — five rules for organising a reference file that
  holds many independent facts under one trigger.
- Whether the guide-shaped facts become gitlore skills instead of memories.
  Deferred by agreement until the pass ends, because `memory-writing`,
  `index-compaction-triggers`, `design-doc-writing` and `green-is-not-evidence`
  all raise the same question and it is one decision rather than four.
- How the `git:*` exclusion actually gets written. `excludedCommands` is
  user-scope `~/.claude/settings.json`, which the classifier denies to the
  agent; the route is the built-in `update-config` skill or the `/sandbox`
  menu. `find:*`, `ls:*` and `claude:*` were agreed alongside it.
- Whether to carry the `cwd-safety` relaxation to that repo, and how. It lives
  at `/Users/david/code/cwd-safety`, outside this session's consent scope, so
  the change needs an explicit go-ahead or a brief. The shape is settled:
  rules 3, 1 and 5c stop blocking and stop rewriting, rule 4 is unchanged, and
  its message must name `cd <root> && <cmd>` explicitly.
- Whether to report the `unsandbox-git-status` findings to that repo as a brief
  — the `permissionDecision: allow` scope hole, and its retirement once
  exclusions are in and verified. Same consent-scope constraint.

## Remaining

- Review the remaining 98 ddaanet memories, continuing down the index-line size
  order recorded in the ledger's table.
- Apply every approved edit in one pass at the end of the review.
- Carry the `` !`cmd` `` findings in
  `plans/ddaanet-memory-review-2d-corpus-scrape.md` into memory when that pass
  runs: expansion is sandboxed by default, `excludedCommands` applies to it,
  PreToolUse hooks do *not* fire on that path, and `mLe` runs the extracted
  blocks concurrently under `Promise.all`.
- Resolve or record the open anomaly in 2d: one unsandboxed `` !`cmd` `` run
  returned the full phantom-mask listing, and three later runs were clean.
  Neither the concurrent `Promise.all` sibling nor a long-lived sandboxed
  background task reproduced it. It decides whether an exclusion delivers clean
  output always or only usually.
- Compact the memory index. It stands over Claude Code's 24.4 KB loader cap, so
  the tail entries do not reach a session, and gitlore's own gate asks for under
  17.1 KB. Retire or merge entries rather than shortening new ones below the
  point where they still route.
