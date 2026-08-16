## Current task

Reviewing all 100 `memory/ddaanet/` facts against the `memory-writing` rubric,
ordered by index-line size largest first, one memory at a time with my human
partner validating each verdict before the next. The running ledger is
`plans/ddaanet-memory-review.md`; it holds the verdict table, the per-entry
reasoning, and the evidence gathered for entries still open. Entry 1
(`memory-writing`) is settled as keep-as-written. Entry 2 (`sandbox-effects`)
has absorbed a decompilation of Claude Code's Bash permission pipeline; the one
factual correction that came out of it is applied to the memory file, but the
six rubric changes proposed for that entry remain unapproved.

A second thread came out of entry 2 and now has its own decisions block in the
ledger: how ddaanet repos should configure `sandbox.excludedCommands`, whether
`unsandbox-git-status` retires in favour of them, and how `cwd-safety` should be
re-scoped now that its subshell rewrite is known to defeat the exclusion matcher
and its `permissionDecision: allow` to circumvent the permission gate. The two
remaining questions there wait on a corpus scrape.

Edits to the other memory files stay deliberately deferred to the end of the
pass, so the index and the fact-file frontmatter descriptions are rewritten once
rather than per entry.
