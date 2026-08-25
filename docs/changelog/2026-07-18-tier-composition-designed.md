# 2026-07-18 — D17 slice 3 (tier composition) designed — free-form multi-tier, ready to spec

Converged the composition mechanism and sliced it 3-i/3-ii/3-iii (see the D17
status line). Key decisions: (1) **discovery by enclosure** — every submodule in
the memory store's own `memory/.gitmodules` is a tier; no tier-name constant,
satisfying "don't hardcode the tier name" (the parent's fixed `gitlore-memory`
name is the asymmetric counterpart). (2) **Line→tier identity by path prefix**,
no sentinel text in either index; composition splices carrier lines up
(prefix-added) and mirrors root tier lines down (prefix-stripped). (3)
**Routing guidance self-describes on the tier** (its `MEMORY.md` frontmatter
`description:`), travels to every consumer, reported at SessionStart for active
tiers — chosen over a local manifest of descriptions because duplicating routing
text per repo is the drift this project exists to kill. (4)
**Ordering + activation in an explicit consumer-local manifest**
`memory/.gitlore-tiers` (listed = active, order = precedence), *not*
`.gitmodules` (incidental add-order, git-porcelain-rewritten) and *not* index
marker text; deliberately edited (never auto-populated), so a half-formed tier
stays invisible. (5) **Mount vs create** distinguished, both ending with the
manifest edited last; the creation gap ("module exists" before "module
self-describes") is harmless precisely because it is not yet listed. (6)
**Compose is mid-session recomposable** via `PostToolUse` on `.gitlore-tiers`,
fail-safe with two validations (no duplicate lines; no manifest entry for an
absent module) — required by the agent-driven add-tier validate-and-reorder
story, ruling out SessionStart-only. (7)
**branch model unified to detached-at-`live`** — memory and tiers both check out
detached at `live` (no named working branch); the per-parent-branch model was a
local checkout handle only, never travelled, and gave no branch-aligned history
(memory ff-pushes to `live` every commit), so dropping it yields one commit path
— collapsing the `branch-vs-live`/`local-vs-remote` split — at the cost of a
resolve-machinery refactor with no compat tax (sole user). Coverage/prune/dedup
stay deferred behind the presence-authority question. Slice sequence: 3-i-a
(propagation-in + routing, no commit path) → branch-model unification (a
Plan-03-level refactor) → tier commit/push lockstep → 3-ii composition → 3-iii
`/add-tier`. Design-doc D17 updated (materialization, routing, composition,
manifest, triggers, add/create, branch-model paragraphs + status); 3-i-a plan
written.
