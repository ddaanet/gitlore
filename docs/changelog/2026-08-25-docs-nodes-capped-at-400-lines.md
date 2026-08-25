# 2026-08-25 — Every `docs/` file is capped at 400 lines, and the checker enforces it

The graph split of 2026-08-20 fixed the hub and left five files that a reader
still cannot take in at one go: `design.md` at 810 lines, `tiered-memory.md` at
718, `evals-best-practices.md` at 930, `installation.md` at 645 and
`commit-gate.md` at 475. At the 80-column hard wrap the graph runs 18–23
tokens a line, so 400 lines lands at 9.1k tokens or under: the line count is the
binding limit and the token budget follows from it. Trimming narration recovers
about 5% — measured on the previous split — so the lever is another cut along a
need-time seam, with concision second.

The seams chosen, one per file. `evals-best-practices.md` splits by its own
section numbers into `evals-llm-as-judge.md` (§5), `evals-agents.md` (§6) and
`evals-operations.md` (§7 and the §10 cookbook); the numbers are unchanged
across all four, so a citation by `§` still resolves. `tiered-memory.md` splits
along the four clusters its own summary already named, into
`index-composition.md` (D29–D31, D34–D37), `index-authoring-sync.md` (D38–D40)
and `tier-stores.md` (D42–D44), keeping D17 and the cluster summary as the
subsystem's entry node. `installation.md` splits install-time from launch from
session, into `memory-redirect.md` (D10) and `session.md` (D5, D11, D14, D21);
D8 moves in from `commit-gate.md`, because it argues remote-creation
confirmation rather than approval. `commit-gate.md` splits what approval *is*
from the scripts that carry it out, into `git-hooks-and-entry-points.md` (D16,
D20). The hub's step lists become `workflows.md` and its configuration
inventory becomes `configuration.md`, and each `### Rejected Alternatives` group
moves to the end of the node whose mechanism it argues about, leaving the hub
one paragraph per group naming what was ruled out.

What the hub keeps is the at-a-glance layer: one conclusion line per decision,
grouped by node, with the group's rejected alternatives named on a *Rejected*
line right under its bullets rather than in a section of their own — a reader
weighing a new decision meets both the call and what was ruled out without a
hop. What had to give to fit that under the cap was mechanism the nodes
already carry in full: the configuration inventory and the branch model's
phase list went to their nodes, and the hub's pointer paragraphs shrank to
one sentence each. The hub lands at 393 lines; a section that grows from here
needs the same treatment rather than a raised cap.

`scripts/check-docs-links.py` gains a blocking `oversized-file` check so the cap
is a gate rather than a note, with two bats cases pinning the boundary — 401
lines blocks, 400 passes. Tokens stay ungated: counting them calls the API,
and the wrap already bounds them. Two more checker changes follow the split.
The orphan scan resolves the bare-basename links nodes use among themselves,
so a node reachable only from a sibling no longer warns. And the hub's
delegation sentence — `(D29–D31, D34–D37) in [name](references/x.md)` — is
now the contract: a node's own summary concludes a decision only when the hub
delegates that number to that node, and a delegation the node does not honour
is blocking `delegation-drift`. A node summarizing itself unasked was how D41
once lost its hub bullet without any check noticing.

Before and after, in lines: `design.md` 810 → 393, `tiered-memory.md` 718 → 187,
`evals-best-practices.md` 930 → 281, `installation.md` 645 → 262,
`commit-gate.md` 475 → 262. Eighteen files under `docs/references/`, the largest
`session.md` at 359.
