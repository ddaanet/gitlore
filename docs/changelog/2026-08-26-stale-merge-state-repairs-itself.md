# 2026-08-26 — A merge state file whose MERGE_HEAD a checkout cleared is classified and repaired, not declared unrecoverable (FR13, D7)

Reported from another repo, from a session where an agent — asked to revert to
the pre-merge state — ran a plain `git merge --abort` in a tier that
`gitlore_yield_merge` had just prepared a `head-vs-remote` merge in. That clears
`MERGE_HEAD` and resets the index while leaving gitlore's state file,
`mine.diff`, `theirs.diff` and `tree` behind. `git checkout` reaches the same
state by a quieter route: including the no-op re-checkout `submodule update`
runs, it calls `remove_branch_state()`, which unlinks `MERGE_HEAD` and
`MERGE_MSG` silently and on success, and a cleanly auto-merged index has no
unmerged entries for checkout to refuse over — so that one leaves the staged
result behind where the abort does not.

Either way the state file outlives the very pointer every gate discriminated on,
and each of them — `pre-commit`, `pre-push`, `commit-memory.sh`,
`push-memory.sh`, `merge-memory.sh` — printed the same sentence: *merge state
file present without `MERGE_HEAD` — manual intervention required*.
`/gitlore:resolve` printed it too, so the documented repair skill could not
repair the one state a user reaches by asking for something perfectly ordinary.

Nothing in the diagnosis needs judgement, which is what makes it the scripts'
work rather than the agent's (D7). The state file records the store, the flavor,
the authority ref and the pre-merge pending commit, and `refs/gitlore/pending`
pins that commit; `gitlore_recover_stale_no_merge_head` reads them and answers
three questions in the order in which each answer decides the next.

**Did a merge land?** A merge commit taking the pinned pending commit as a
parent other than its first is that merge. The search covers every ref *and*
every reflog, because a merge that landed and was then checked out away from is
reachable from no ref at all — and `git fsck` counts the reflogs among its
roots, so the obvious `fsck --unreachable | grep commit` reports nothing for
precisely the case that has to be caught. Where the merge already contains HEAD
and the tree is clean, HEAD returns to it and the leftover state is cleared,
which loses nothing by construction; where the store is dirty or carries commits
the merge does not, nothing is touched and the three commands to inspect and
restore it are printed with every path and sha substituted. That second form is
also what a by-hand recovery lands on afterwards: with HEAD on the merge, the
next gate takes the first branch and cleans up on its own.

**Is a merge result still staged?** The index survives the checkout that took
the pointers, and what it holds may be a synthesis the user has already
approved. `MERGE_HEAD` and `MERGE_MSG` are written back — git's own wording, so
the continuation commits it as the merge it is — and the store is then exactly
where `gitlore_prepare_merge` leaves one, so the ordinary directive asks for the
sub-agent and `continue-after-merge`. Deliberately not abort-then-retry, which
runs `merge --abort` and would discard the staged tree along with the worktree
it was written into. Restoring is refused when HEAD is not the authority the
state file names: that commit is what the merge was built on, and re-attaching a
second parent to some other HEAD would record a merge nobody prepared, so both
shas are reported instead.

**Neither?** The merge is dead. HEAD goes back onto the pending commit *before*
the pin is dropped — after a preparation that pin is the only reference to the
divergent side, so clearing it with HEAD still on the authority would orphan the
commit the merge existed to land, and the gate that follows would find a store
with nothing to merge. Then every artifact goes and the guard returns 0, so the
caller carries on and prepares the merge again if the divergence is still there.
The artifacts are deleted rather than moved aside: the next preparation
recomputes each of them from the two sides, so a copy would be a stale duplicate
of a file about to be rewritten.

One dead end remains, and keeps the old wording. A state file naming no pending
commit, with the pin gone too, leaves nothing that can decide whether the merge
landed; guessing there would be the one move that can lose committed memory.

`SessionStart`'s tier pass still refuses to check out over a prepared merge. The
repair reads the index to decide what to do, and a session start that provokes
the damage every time would make a recovery path into the normal one.

Six cases in `tests/resolve_recovery.bats` — one per branch, plus one driving
`/gitlore:resolve` itself — and one in `tests/merge_memory.bats` at the
incident's own geometry: `head-vs-remote`, prepared by `merge-memory.sh`, undone
by a hand-run `git merge --abort`, and asserted to re-prepare with its
`publish: "no"` mark intact. Each was watched failing against the unchanged
guard first. The landed-merge case constructs a merge reachable from no ref and
asserts that `fsck --unreachable` does not name it, so the imprecise test cannot
be reintroduced without going red. Every repair says what it disposed of before
it acts, and that sentence is pinned rather than left to the reader's goodwill.
