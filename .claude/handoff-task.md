## Current task

Reviewing all 100 `memory/ddaanet/` facts against the `memory-writing` rubric,
ordered by index-line size largest first, one memory at a time with my human
partner validating each verdict before the next. The ledger now spans
`plans/ddaanet-memory-review.md` — a hub holding the verdict table, entry 1 and
entry 1b — plus parts 2a-2d carrying entry 2. Entry 1 (`memory-writing`) is
settled as keep-as-written. Entry 2 (`sandbox-effects`) still has six rubric
changes unapproved. Entry 3 is `green-is-not-evidence` at 690 B, then
`index-compaction-triggers` at 590 B.

The sandbox-exclusion thread that came out of entry 2 has both of its blocked
decisions taken: `git:*` as the exclusion entry, on coverage grounds since no
narrow prefix reaches `git -C`; and a relaxed `cwd-safety` that always allows a
`cd`-prefixed composite and keeps only the rule-4 drift block. Neither is
implemented — both touch files outside this session's consent scope.

Edits to the memory files themselves stay deliberately deferred to the end of
the pass, so the index and the fact-file frontmatter descriptions are rewritten
once rather than per entry.
