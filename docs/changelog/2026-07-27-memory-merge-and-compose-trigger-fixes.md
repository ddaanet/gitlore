# 2026-07-27 — The memory merge stopped reading an index as prose, and the compose trigger stopped trusting tool calls

Five changes, one shape: what a merge or a batch *declared* is a poor proxy for
what it *did*. (1) `gitlore_prepare_merge` runs git's three-way with
`merge.conflictStyle=diff3`, so a conflict carries the `|||||||` base — which
side changed a line is unknowable from two versions, and that is exactly what a
semantic merge has to judge. (2) A second, entry-wise pass
(`scripts/lib/index-merge.sh`) re-merges every `MEMORY.md` in the merge, keyed
on the pointer path. Line-wise merging fails an index in both directions: two
sides inserting *different* facts at the same offset conflict although nothing
is in dispute, and two sides inserting the *same path* at different offsets
merge **clean** into a duplicate pointer — the state `gitlore_compose_check`
refuses on, so the silent success is what strands the store. That is why the
pass runs on every index rather than only the flagged ones, and why
`conflicted_files` is the union of git's unmerged entries with
`gitlore_conflicted_indexes` (the pass resolves in the worktree without
staging). A side that already names one path twice is *declined*, not collapsed
— collapsing would silently drop a line, and the malformed index is
`compose_check`'s to report. (3) The continuation's compose is **up-only**: the
merged tier's facts must reach the root index because that is the only surface
recall reads, but mirroring down would write a store the user never reviewed as
a side effect of approving one index, and would advance
`refs/gitlore/compose-base` past a reconciliation that never happened — making
the next full pass read every root-side addition as a deletion. Splice-up
correspondingly reads `gitlore_compose_tier_bullets`, not the carrier file, or
root-authored tier lines the carrier has not received would be dropped.
In-session index→tier propagation stays the hooks' job. (4) The merger sub-agent
is briefed with `gitlore-merge-mine.diff` (base→authority),
`gitlore-merge-theirs.diff` (base→pending) and `gitlore-merge-tree`, named in
the state file and removed by the single `gitlore_clear_merge_state`;
`No conflict.` became an explicit valid answer, since divergence is a git fact
and compatible sides are the common case. (5) The `PreToolUse` matcher is now
`Write|Edit|Bash` and both `PostToolBatch` consumers ignore `.tool_calls[]`
entirely — the sync `cmp`s the pre-batch stash, compose compares a pre-batch
checksum stamp, and each owns its own baseline file so hook order does not
matter. A `sed -i` on `MEMORY.md` used to land with neither propagation nor
composition running; a memory file existed only to warn about it, and is retired
with this entry. The `Bash` arm's cost/benefit is measured rather than argued —
see D17's "The `Bash` arm is measured, not assumed" for the transcript-corpus
counts and the timing — and the widened matcher was confirmed live on this
repo's own store: a `sed -i` rewriting one tier line's hook in
`memory/MEMORY.md` propagated into `ddaanet/feedback_no_askuserquestion.md`'s
frontmatter and mirrored down into the carrier in the same batch, advancing
`refs/gitlore/compose-base`; restoring the three files returned the ref to its
prior value. That probe also corrected a wording carried in both post-hooks and
D17: `PostToolBatch` fires once per **tool batch**, not once per user turn — a
single turn fired it twice. 19 new cases (`tests/index_merge.bats`,
`tests/resolve_merge_briefing.bats`) plus rewrites of
`tests/cc_hook_index_compose.bats` and the Bash-trigger and stranded-stash cases
in `tests/index_sync.bats`; every new assertion was turned red by a deliberate
fault first. One latent bug surfaced on the way: `x=$(pipeline || echo '[]')`
*appends* the fallback when `pipefail` propagates a producer's failure after
`jq` already printed, handing `--argjson` two JSON documents — the `||` belongs
outside the substitution.
