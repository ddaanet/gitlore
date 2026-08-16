## Open decisions

- Approve or reject the six changes proposed for `sandbox-effects`, set out in
  full under entry 2 of `plans/ddaanet-memory-review.md`: route the
  read-only-inspection standing default to the `prohibitions` plugin rather than
  to `shared-claude.md`; change the `apply-seccomp: unshare(CLONE_NEWUSER)`
  remedy from retry-unsandboxed to retry-once-unchanged; demote the
  strict-sandbox-mode section and state unsandboxed-fallback plus auto mode as
  the baseline; replace the claim that `Edit` may write `.claude/settings.json`
  with the built-in `update-config` skill; name backtick-bang expansion as the
  mechanism behind the sandboxed slash-command `## Context` block; and merge the
  `/add-dir` section into `classifier-denied-self-config`, carrying the *external
  repo outside the trusted source control org* verdict string and the
  ask-rules-are-not-authorization residue with it.
- Approve or reject the structure section proposed for `memory-writing` under
  entry 1b — five rules for organising a reference file that holds many
  independent facts under one trigger.
- Whether the guide-shaped facts become gitlore skills instead of memories.
  Deferred by agreement until the pass ends, because `memory-writing`,
  `index-compaction-triggers`, `design-doc-writing` and `green-is-not-evidence`
  all raise the same question and it is one decision rather than four.
- `git:*` versus the narrow entries `git status:*`, `git add:*`, `git commit:*`,
  `git ls-files:*`. `git:*` unsandboxes roughly a third of all Bash traffic, and
  since 75.9% of git-bearing calls are compound the neighbours ride free with
  it. Blocked on the corpus scrape.
- How `cwd-safety` is re-scoped, which hinges on how often `cd <dir> && …` and
  `git -C` are actually issued. Blocked on the same scrape. The shape proposed
  in the ledger: permit `cd <dir> && …` and let cwd drift, block a
  non-`cd`-prefixed command when cwd is not root, allow a bare `cd <root>` as
  the restore, and stop advertising the `( … )` form.
- Whether to report the `unsandbox-git-status` findings to that repo as a brief —
  the `permissionDecision: allow` scope hole, and its retirement once exclusions
  are in and verified. That repo is outside this session's consent scope, so
  either write needs an explicit go-ahead.

## Remaining

- Split `plans/ddaanet-memory-review.md` into chunks of at most 400 lines. It
  has outgrown a single file.
- Scrape the session corpus for `cd <dir> && …` and `git -C` frequency, which
  settles the two blocked decisions above.
- Review the remaining 98 ddaanet memories, continuing down the index-line size
  order recorded in the ledger's table. Entry 3 is `green-is-not-evidence` at
  690 B, then `index-compaction-triggers` at 590 B.
- Apply every approved edit in one pass at the end of the review.
- Compact the memory index. It stands over Claude Code's 24.4 KB loader cap, so
  the tail entries do not reach a session, and gitlore's own gate asks for under
  17.1 KB. Retire or merge entries rather than shortening new ones below the
  point where they still route.
