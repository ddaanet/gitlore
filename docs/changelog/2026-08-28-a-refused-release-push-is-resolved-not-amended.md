# 2026-08-28 — A release push refused by a memory merge is resolved and re-pushed, never amended (D46)

Cutting a release with a gitlore-mounted toolkit exposed a window the design
had no decision for. The release recipe commits a version bump — `pre-commit`
pins memory into it — tags, then pushes; `pre-push` publishes memory first,
and if any store's `origin/live` moved since the commit it prepares a merge
and refuses, leaving the commit and tag local. The window is human-paced: the
FR11 approval on the release commit and the review of the merge both sit
inside it, and it reopens whenever `origin/live` moves again while a merge is
under review.

The repair on the table was a scripted `commit --amend` plus `tag -f` on the
resume path, so the tagged commit's gitlink would name the merged memory.
Reasoning from the invariant instead: the gitlink a parent commit records is
always an ancestor of memory's `live`, or `live` itself — `pre-commit` makes
it `live`, and every merge keeps the pending commit as its second parent — so
the first `live` push that succeeds publishes it, and NFR5's ordering makes a
parent push that goes through imply a public gitlink. The window closes on a
successful push and on nothing else; the amend bought only a tag whose tree
names the merged memory, at the price of rewriting a tagged commit, forcing a
tag, and sequencing after the stale-merge guard. A gitlink behind memory's tip
is the resting state every other memory advance already leaves.

Two things are now stated in `git-hooks-and-entry-points.md` that were
previously only a comment in `scripts/git-hooks/pre-commit` or nowhere: the
replay stand-down's contract that a plain `--amend` on the tip is authored-now
(a marker added to the list must be a replay, never a tip rewrite), and the
ancestor invariant itself. No script changed. The toolkit side is a brief in
`claude-plugin-dev`: its `resume-release` already recovers the state, and the
loop is resolve, then resume, until the push lands.
