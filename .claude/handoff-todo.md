## Open decisions

- Whether the newly measured classifier cost changes the settled `git:*`
  decision. Once a command leaves the sandbox it reaches the auto-mode
  classifier, which refused `ls -a | wc -l; echo ...`, `find ... | wc -l;
  echo ...` and `claude --version; echo ...` while allowing `ls -a; echo ...`,
  `find ...; echo ...`, `git log ...; echo ...` and a bare `claude --version`.
  No stable predicate separates them, and the pipe is not it. Sandboxed calls
  were auto-allowed with no classifier involvement, so the denials are new, and
  `git:*` carries roughly a third of Bash traffic. Recorded in 2c; the
  mitigation on the table is shape — keep an excluded command in its own call —
  rather than a settings change.
- Whether `claude:*` actually runs unsandboxed. Three of the four exclusions are
  confirmed by the `${TMPDIR-UNSET}` discriminator; `claude:*` rests on the
  shared matcher alone, because every form carrying the discriminator was
  denied.
- Where 2c's finding (2) lands — `updatedInput` alone defers to the full
  permission pipeline, `permissionDecision` settles it. No existing fact owns
  it: `hook-output-channels` owns the channels and
  `hook-cannot-inject-tool-calls` owns `updatedInput`'s existence. The lean is
  to combine the hook-related memories rather than add a fourth.
- Whether constrained generation or unconstrained-then-review produces better
  facts — the question 4c deliberately left open for the
  `gitlore:memory-writing` conversion, settleable by `just evals`.

## Remaining

- Run the rubric on entry 5, `hook-input-schema` (502 B), and put a verdict up.
  The body was read; nothing was decided.
- Review the remaining 96 ddaanet memories, continuing down the index-line size
  order recorded in the ledger's table.
- Apply every approved edit in one pass at the end: entry 3's relink to
  `[[spec-enumerations-need-rederiving]]` and its redrafted 690 B index line,
  and entry 2's changes (a) through (f) as ruled.
- Build the two artifacts entries 1 and 4 resolved to — the
  `gitlore:memory-writing` skill and the manual `/gitlore:index-audit` command —
  with the design decision going to `docs/design.md` rather than to a memory.
- Carry into memory the `` !`cmd` `` findings in 2d and the classifier-denial
  cost in 2c.
- Resolve or record 2d's open anomaly: one unsandboxed `` !`cmd` `` run returned
  the full phantom-mask listing while three later runs were clean, and neither
  the concurrent `Promise.all` sibling nor a long-lived sandboxed background
  task reproduced it. It decides whether an exclusion delivers clean output
  always or only usually.
- Retire enough of the index to restore headroom. The two conversions clear
  Claude Code's 24.4 KB loader cap by only about 118 B, leaving retirement as
  the remaining lever.
