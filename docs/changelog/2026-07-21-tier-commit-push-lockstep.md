# 2026-07-21 — Tier commit/push lockstep — a fact authored in a tier now persists and publishes with it

Before this, writing into `memory/ddaanet/` left the tier dirty, its HEAD
unmoved, and memory's `git add -A` staging nothing — so the memory commit had
nothing to record and the parent commit was *blocked* by a bare "nothing to
commit" from inside the hook. `gitlore_sync_tiers_to_live` now commits every
dirty mounted tier and ff-advances its local `live` **before** memory's own
`add -A` (the gitlink moves first, so the memory commit records it rather than
lagging one behind — the same ordering the parent's gitlink staging exists to
enforce), and `pre-push` pushes each tier's `live` to its own remote **before**
memory's, so a published pointer always resolves. Two open decisions closed by
writing it: **one approval summary per episode**, reused verbatim as the commit
message in every store touched (the user approves a set of writes, not of
repositories; what the prompt owes them is grouping by destination, since a tier
line is more public than a project one), and
**no recursing hooks in the memory store** — recursion is driver-side, as the
parent already drives memory, avoiding a second round of
`--local-env-vars`/`GIT_INDEX_FILE` handling and keeping `memory-pre-commit` a
pure FR11 gate. That gate is now emitted into each tier too (with its own
`gitlore.hooksDir` mirror, since the wrapper's `git config` reads the store it
fires in), so a naked tier commit is blocked exactly like a naked memory commit.
Scope is every **mounted** tier, not just the manifest-active ones: dormancy
governs routing, and dropping a dormant tier's writes would be data loss. Every
loop guards `[ -e "$tierpath/.git" ]` first — a `git -C` into an unchecked-out
submodule escapes to the enclosing repo and would have committed *memory* under
the tier's name. Tier divergence is detected at the remote push and reported by
tier name; automated *resolution* arrived separately (2026-07-22, one merge
policy at every level). `scripts/emit-memory-gate.sh`'s `[ -n … ] && git …`
hooksDir mirror became an `if` — not a bugfix: an and-list whose test fails is
inert mid-script under `set -e` (checked, rather than assumed, when the
changelog first claimed otherwise), and only bites when it lands *last* in a
script or function, where its status 1 becomes the exit status. The `if` form
means neither statement acquires that hazard by later being moved. 342 unit + 31
integration green.
