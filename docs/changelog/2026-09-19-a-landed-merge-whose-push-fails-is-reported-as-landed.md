# 2026-09-19 — A landed merge whose push fails is reported as landed (D49, D52)

A deliverable review of the repair-and-continuation work found one exit the
allow-list misread. A merge continuation whose `live` advance or `origin` push
fails for a reason other than divergence exits 1 after the merge commit, with
`gitlore: pushing '…' failed, and not because of divergence`, and is the one
path that prints the rest remedy
`gitlore: tier '<t>' stays on the merge commit … Run:`. Both readers filed it as
unrecognised, so a merge that had landed was reported as of unknown fate, and
the skill's note that a printed remedy is still to run was framed around its
**Loop**, which that outcome never reaches. The `memory-merger` agent and
`/gitlore:resolve` now recognise the line: the merge landed, the push failed,
there is no re-synthesis and no loop, and any remedy printed is outstanding
whenever it was printed. Both also name the two post-commit sites that can
prepare a fresh merge — the local `live` advance and the push of `live` to
`origin`.

The post-loop publication pass in `gitlore_push_stores` checks ancestry against
`origin/live` directly, as the behind arm's retry does. Its separate arm for a
missing `origin/live` was unreachable — every tier that reaches the pass with a
local `live` was pushed by the loop, classified against `origin/live` by the
behind arm, or given its `live` by a take fast-forwarding from it — and
redundant, since a failed ancestry check pushes anyway. The root-index refusal
header and its prefixed lines are printed by one helper,
`gitlore_adopt_print_root_refusal`.

Two rejected alternatives for the repair's scratch copy are recorded under D52
in `references/tier-arrival-repair.md`: a scratch directory in the tier's
gitdir, and a sweep of stale `gitlore-repair.*` directories on the next repair,
which races a concurrent take. The node also states the `/tmp` fallback, the
retry refusal's default remedy, and the refused `live` advance once.
