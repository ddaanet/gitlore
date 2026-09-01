# Merge-state recovery

What a gate does when it meets a merge state file it did not just write: the
marker-before-prepare discipline, and the classification of every shape a
crashed or externally-disturbed merge can leave. The merge machinery that
writes these states is in [merge-and-resolve.md](merge-and-resolve.md); this
node is what you need when a store holds a `gitlore-merge-state` you have to
reason about.

---

A crashed merge leaves the state file behind, and every gate guards on it. The
file goes down *before* the preparation starts, not after it succeeds:
`gitlore_yield_merge` writes a marker naming the store, the flavor, both sides
and the continuation, then prepares the merge, then overwrites the marker with
the full state file. Every window inside `gitlore_prepare_merge` — a killed
`push-memory.sh`, a tool timeout — therefore leaves a file the next gate
classifies, and the marker is dropped again if the preparation refuses outright.
A marker is told from a full state file by `changed_files`, the first field the
merger sub-agent reads and the one no marker can carry; wherever a state file is
about to reach that sub-agent, `gitlore_complete_merge_state` fills a marker in
from the merge the store already holds.

With `MERGE_HEAD` present the store sits exactly where `gitlore_prepare_merge`
leaves one, so the directive is the ordinary `continue-after-merge` and the
merge is handed back to the sub-agent: **a prepared merge is always continued,
never discarded.** By the time a gate meets it again the sub-agent may already
have synthesized and staged an answer, and nothing in the store tells that apart
from a merge no one has touched.

`MERGE_HEAD` with *no* state file is then not gitlore's at all — a `git merge`
run in the store by hand, or by an agent asked to merge one. It blocks and is
reported with the store's own status and `merge --abort` commands, never
touched: nothing there says what the merge was for, and it may hold work in
progress.

The accepted trade is a merge whose authority moved while it waited — someone
pushed to `origin/live` meanwhile. It lands against the authority it was built
on, and the continuation's own fast-forward (`push . HEAD:live`, then
`push origin live` for a `head-vs-remote` merge) is then refused as a
non-fast-forward, which re-prepares the merge against the current authority and
yields again. One extra cycle, against re-synthesizing every merge that outlives
its session — and re-preparing on sight never avoided it either, since that too
merely fixed the authority as of whenever the gate happened to run.

Without `MERGE_HEAD`, the guard
classifies from the pinned pending commit and the state file's own fields, and
repairs. Three things produce that state, and they leave different remains. A
preparation interrupted between its checkout and its merge leaves its marker,
the pin, and HEAD on the authority, with nothing merged. A
plain `git merge --abort` run in the store drops the pointers *and* resets the
index, so nothing of the merge survives but gitlore's own files, while
`git checkout` — including the no-op re-checkout `submodule update` runs — calls
`remove_branch_state()`, which unlinks `MERGE_HEAD` and `MERGE_MSG` silently
while leaving the staged result behind (a cleanly auto-merged index has no
unmerged entry for checkout to refuse over).

- **A merge landed.** A merge commit taking the pinned pending commit as a
  parent other than its first *is* that merge, wherever HEAD sits now. Searched
  across refs **and** reflogs: a landed merge HEAD was moved off is reachable
  from no ref, and `git fsck` counts the reflogs among its roots, so
  "is there an unreachable commit" is silent on exactly this case. HEAD returns
  to the merge when doing so can lose nothing — the merge already contains HEAD
  and the tree is clean — and the commands to do it by hand are printed
  otherwise.
- **A merge result is staged.** The index survives the checkout that took the
  pointers, and what it holds may be a synthesis the user has already approved,
  so `MERGE_HEAD` and `MERGE_MSG` are written back and the directive asks for
  the sub-agent again — the same continuation the `MERGE_HEAD`-present case
  gets, and for the same reason: discarding the merge would take the staged tree
  with the worktree it was written into. Refused when HEAD is not the authority
  the state file names, since that commit is what the merge was built on.
- **Neither, and the file is a marker.** The preparation was interrupted before
  its merge ran. Disposed of exactly like a dead merge below, with the message
  the store's own remains support rather than an abort nobody performed.
- **Neither.** The merge is dead — the `merge --abort` shape. HEAD goes back
  onto the pending commit *before* the pin is dropped, since after a preparation
  that pin is the only reference to the divergent side; every artifact a
  preparation wrote is deleted, and the gate carries on, preparing the merge
  again if the divergence is still there.

The artifacts are deleted rather than moved aside because the next preparation
recomputes each of them from the two sides. One dead end remains: a state file
that names no pending commit, with the pin gone too, leaves nothing that can say
whether the merge landed, and the message says so.
