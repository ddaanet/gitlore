## Open decisions

- Approve or reject the six changes proposed for `sandbox-effects`, listed in
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
  independent facts under one trigger, drawn from what is wrong with
  `sandbox-effects`.
- Whether the guide-shaped facts become gitlore skills instead of memories.
  Deferred by agreement until the pass ends, because `memory-writing`,
  `index-compaction-triggers`, `design-doc-writing` and `green-is-not-evidence`
  all raise the same question and it is one decision rather than four.
- Whether to report the `unsandbox-git-status` scope finding to that repo as a
  brief. Its hook returns `permissionDecision: allow` together with an
  `updatedInput` that carries the whole `tool_input` through, so any command
  holding a matching segment runs unsandboxed *and* pre-approved — where the
  native `excludedCommands` mechanism unsandboxes without pre-approving. The
  repo is outside this session's consent scope, so the brief needs an explicit
  go-ahead.
- What to do about sandbox exclusions now the matcher is understood. The
  `"git status"` entry in `~/.claude/settings.json` is an exact match and covers
  2.8% of real `git status` traffic, while the plugin covers the rest, so
  dropping either changes accuracy sharply. Open sub-choices: add `git:*`
  (76% of git-bearing calls are compound, so neighbours lose the sandbox too),
  `find:*` (100% of its traffic needs it), or `ls:*` (30%).
- Whether the new `excludedCommands` section belongs in `sandbox-effects` at
  all, or as its own memory: its trigger — configuring an exclusion, or
  explaining why an unrelated command ran unsandboxed — is distinct from "the
  sandbox broke my command".

## Remaining

- Review the remaining 98 ddaanet memories, continuing down the index-line size
  order recorded in the ledger's table. Entry 3 is `green-is-not-evidence` at
  690 B, then `index-compaction-triggers` at 590 B.
- Apply every approved edit in one pass at the end of the review.
- Compact the memory index. It stands at 26,327 B against Claude Code's 24.4 KB
  loader cap, so the tail entries do not reach a session, and gitlore's own gate
  asks for under 17.1 KB. Retire or merge entries rather than shortening new
  ones below the point where they still route.
