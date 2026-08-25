# 2026-07-14 — Revised D17 — index one-liner is canonical; composition is structural, not frontmatter-derived

A git-history audit of this repo's own memory refuted D17's original
"frontmatter is the single source of truth" premise: the root `MEMORY.md`
one-liner and the frontmatter `description` **drift bidirectionally** — the
agent only has the always-loaded root index in context, so it revises whichever
surface it sees and the other rots, in *both* directions
(`feedback_memory_retrieval_in_practice` = fresh index / stale frontmatter;
`reference_git_hook_env_leak` = the reverse). Retrieval instrumentation (U1)
also showed both surfaces feed CC's selection classifier, but only the index
line is always-loaded and reliably recall-reachable (100% vs 75%). Corrections:
(1) the **index one-liner is canonical**; **no** mechanism derives index text
from frontmatter (old "recompose owns/derives the index" → Rejected
Alternatives). (2) The recompose is **structural** — coverage (a net-new file's
line seeded from frontmatter only), prune, tier-block placement/relocation,
dedup — owning line *presence/placement*, never *text*; root-index writers are
disjoint by aspect, not by line-set. (3) New **authoring-time one-way sync**
(`PreToolUse`+`PostToolUse(Write|Edit)`) mirrors index-hook →
frontmatter-`description` only (index is canonical; a bidirectional sync
resolves conflicts by tool-call order and would let the weaker frontmatter
clobber a curated index hook — corrected 2026-07-15); propagates only the
changed line, complementary to the structural pass. (4) The
**one-time reconcile** handles the harmful *stale-index* direction the one-way
sync can't (a semantic call), must follow sync deployment (else it re-drifts),
is per-project + once-per-tier, and is opportunistic/lazy (an optional
`/gitlore:reconcile`). Implementation sequence when scheduled: one-way sync →
reconcile (dogfood here) → structural recompose + nested tier. Design only; no
code change.
