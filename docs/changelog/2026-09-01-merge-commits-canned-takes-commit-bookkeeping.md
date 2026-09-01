# 2026-09-01 — Merge commits are canned and unprompted, and explicit takes leave a clean store (D49)

The recurring irritant was a commit owed after every push or merge: a tier
take staged the moved gitlink and recomposed root index and stopped, so the
memory store sat dirty until the next FR11 episode explained bookkeeping it
did not author. The reframe that settled it: both parents of every gitlore
merge already passed an approval gate — the local side at its own FR11
commit, the upstream side in the repo that published it — so a merge is
automated from the human's perspective, and prompting for one gates a
decision already made.

FR11 now states the exemption. A divergence merge lands under a canned
message — `merge <merged-repo> from <consumer>`, body listing the
second-parent (local) subjects, because every other consumer of a shared
tier's history already holds the first-parent side and what the merge brought
into `live` is the news. A tier take commits its pair in the memory root as
`Update MEMORY.md for <tier> tier merge.` with the taken subjects as body, so
a fast-forward take is recorded despite creating no tier commit. The resolve
skill keeps the parent agent's review of the sub-agent's synthesis and drops
the user escalation.

The line between committing and not is intention: explicit operations —
`/gitlore:merge`, `/gitlore:push`, a resolve continuation — leave a clean
store; the implicit SessionStart fast-forward still commits nothing. Push now
takes a behind store inline (attempt → take → attempt again) instead of
naming `/gitlore:merge` as an errand, and its report credits only tips the
store held before the run, so a take is never reported as a publication.

Two mechanics fell out of dogfooding the tests. Taking goes root-first, the
mirror of the publish order: an upstream root commit already records the tier
commits it names, so taking it first leaves each tier merely behind, where
tiers-first manufactures a divergence out of two fast-forwards meeting each
other's bookkeeping. And the canned commit is guarded by a beyond-the-pair
dirty check: a root store holding unapproved work before the take keeps the
old staged-pair discipline, because a bare `commit` of the pair would fold the
episode's unapproved index edits into an unprompted commit.

The merge-state classification moved to its own node,
`merge-state-recovery.md`, to keep `merge-and-resolve.md` under the 400-line
cap with D49's argument in it.
