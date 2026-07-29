## Current task

Nothing in flight. The FR11 approval-clause change is complete and verified: the clause is now a sentence-final block carrying a literal body template — one paragraph per changed memory file, `**<Kind> <tier>/<slug>:**` prefix, MEMORY.md excluded from the listing.

The only live thread is the memory-store cleanup below, untouched this session.

## Open decisions

- `handoff`'s `scripts/_checkpoint-lib.sh` still renders gitlore's clause mid-sentence (`"…then a body with $clause."`), which now prints a multi-line block inside a sentence — degraded rendering, not a break, and its own tests use a single-line fixture clause so they stay green. The proposed patch: move `"$clause"` to its own trailing `printf` argument after a blank line, and reword the sentence to `"Summarize these changes as a commit message, its title line at most 72 characters."` — keeping the 72-char limit, which the clause does not carry, and dropping the structure words it does. Read-only rule for David's other repos: he applies it.

- Upstream's index compaction (`b044d35`/`d7a39ed`) cut `phantom dotfiles`, `own hooks.json unlink EROFS` and `a brief dropped there leaves your task frame` from index lines. Each literal now has zero occurrences anywhere in the index, so those facts are unreachable by their symptom strings even though the bodies still carry them. Restore the triggers, or accept the loss as intended compaction? The parallel `PostToolBatch` cut was restored on different grounds — it fell to one occurrence on a wrong line, which misroutes rather than merely losing reach.