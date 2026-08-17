## Open decisions

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
  retry-once-unchanged, now confirmed live; demote the strict-sandbox-mode
  section and state unsandboxed-fallback plus auto mode as the baseline; replace
  the claim that `Edit` may write `.claude/settings.json` with the built-in
  `update-config` skill; name backtick-bang expansion as the mechanism behind
  the sandboxed slash-command `## Context` block; and merge the `/add-dir`
  section into `classifier-denied-self-config`, carrying the
  external-repo-outside-the-trusted-source-control-org verdict string and the
  ask-rules-are-not-authorization residue with it.
- Entry 2 change `(f)`, the restructure: one section per symptom with the
  `index.lock` three-case discriminator, one section on the escape and its
  `$TMPDIR` cost, and a lead symptom → section map. Omitted from the previous
  enumeration of six changes, still unruled.
- Entry 1b: approve or reject the five rules for organising a reference file
  that holds many independent facts under one trigger. They now land in the
  `gitlore:memory-writing` skill body rather than in a memory.
- How the `git:*`, `find:*`, `ls:*` and `claude:*` sandbox exclusions actually
  get written. `excludedCommands` is user-scope `~/.claude/settings.json`, which
  the classifier denies to the agent; the route is the built-in `update-config`
  skill or the `/sandbox` menu.
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
- Retire enough of the index to restore headroom. It sits at 25.6 KB against
  Claude Code's 24.4 KB loader cap, so the tail never reaches a session; the two
  conversions take it to roughly 24.9 KB, clearing the cap by about 118 B and
  leaving retirement as the only remaining lever.
