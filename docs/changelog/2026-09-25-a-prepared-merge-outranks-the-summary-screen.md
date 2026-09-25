# 2026-09-25 — A prepared merge outranks the summary screen

The three defects the D56 checkpoint review found and left, closed.

**The no-summary screen sat ahead of the stale-merge guard.** A commit that
lands and then fails to fast-forward `HEAD:live` has consumed its approval and
prepared a merge, whose checkout leaves the store dirty. The next
`PostToolBatch` therefore arrived with a trigger, a dirty store and nothing
approved — the exact shape the missing-summary screen answers — so it asked the
agent to summarize the pending changes and get approval for them, in front of a
merge `/gitlore:resolve` owns and both of whose sides were already approved
(D49). The summary would not have helped: the guard inside
`gitlore_sync_memory_to_live` refuses on the merge either way. Both entry points
now run the guard first — `commit-memory.sh` after its own `-m`/`-F` write, so
an approval arriving with the call is kept for the retry — and
`memory-commit-batch.sh` skips its screen when the store is mid-merge, letting
the run re-emit the directive. That directive gets an arm of its own in the
hook's failure discrimination, ahead of the freshness arm that would have
dropped it, and the landed-then-failed arm now reads the approval's *pre-run*
state rather than inferring it from the screen above.

**The clean-memory branch removed one IPC file and named two.** A trigger on a
clean store now takes the message file with it, which is what makes "both IPC
files have been removed" true: a summary left behind covers a store with nothing
pending, and the next dirty episode needs its own approval regardless.

**The blank-approval predicate was spelled out twice.** It is
`gitlore_approval_present` in `scripts/lib/util.sh`, called by both entry points
— one definition for what "no summary" means. Its merge-state neighbour,
`gitlore_store_mid_merge`, carries the "not clean" half of
`gitlore_detect_stale_merge_state` for the callers that cannot reach it:
`memory-commit-batch.sh`, which sources only `util.sh`, and
`index-compose-check.sh`, which `resolve.sh` sources, and which had that
predicate spelled out inline with a comment saying why.

**A `-I` flag read as a first-person pronoun.** `check-memory-hygiene.py` blanks
inline code spans within a line, so a span a hard-wrapping formatter broke
across two left its tail in the prose the checks read, and a trailing `-I` in a
`grep` invocation blocked the gate. `FIRST_PERSON` takes the `(?<![-\w])` guard
`DEICTIC` already carries for compounds.
