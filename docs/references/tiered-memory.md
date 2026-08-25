# Tiered memory — decisions D17, D26–D28, D32, D33

The entry node for FR15 (tiered memory) — the mechanism `design.md`'s D17
points at. Motivation, FR15 itself and the Architecture overview live in
`design.md`; the decision-level detail is here and in three sibling nodes. Most
of it is needed only when touching this subsystem; the exception is the
tier-store trio D42–D44, which the commit and merge paths reach from outside
it.

---

**D17 — Tiered memory (FR15): nested submodules plus structural index
composition**

FR15 calls for shared tiers (a truly-global `lore`, an org-scoped `ddaanet`, …)
surfacing in *every* participating repo alongside its local memory, without a
flat merge that would blow the always-loaded index budget. Across N sibling
repos, `user`, CC-platform `reference` and portable `feedback` facts duplicate
and drift, while `project` facts are correctly repo-local. The design keeps
Anthropic's memory structure — index, files, agentic recall — and upgrades only
gitlore's *composition* of the root index.
The mechanism is a subsystem rather than a single call, so its decisions are
recorded individually as **D26–D40 and D42–D44**, across this node and three
siblings:

- **D17** tiered memory (FR15): nested submodules plus structural index
  composition
- Retrieval and routing, here — **D26** the root index one-liner is canonical ·
  **D27** materialization by enclosure · **D28** routing without a content
  classifier · **D32** mount and create · **D33** a tier's always-on conventions
- Composition, in [index-composition.md](index-composition.md) — **D29**
  composition is placement · **D30** the tier manifest · **D31** compose
  triggers and validation · **D34** presence authority · **D35** the
  welded-line refusal · **D36** two projections · **D37** order as a merge
  input
- The authoring surface, in
  [index-authoring-sync.md](index-authoring-sync.md) — **D38** the one-way sync
  · **D39** the routing-key advisories · **D40** pre-existing drift
- Stores and merges, in [tier-stores.md](tier-stores.md) — **D42** tier
  lockstep · **D43** tier pinning · **D44** tier merges. All three assume the
  detached-at-`live` branch model, which is D41, in
  [merge-and-resolve.md](merge-and-resolve.md).

**D26 — The root index one-liner is canonical; frontmatter is a secondary
surface**

*Empirical grounding (retrieval instrumentation, 2026-07-14; full evidence trail
in `docs/references/cc-memory-retrieval.md`).* CC auto-recall was characterized
in both `--print` and a real interactive (tmux PTY) session against a scratch
`autoMemoryDirectory`:

- Only the **root `MEMORY.md`** is always-loaded; a nested `team/MEMORY.md` is
  **not** auto-loaded.
- Bodies are **not** bulk-loaded. Recall is a **tool-gated `Read`** of a
  selected file (surfaced interactively as "Recalled 1 memory"; an auto-issued,
  empty-thinking Read in the transcript), steered by the root index. Disable
  file tools → no body, in both modes.
- A file listed in the root index recalls reliably (100% in probes); an
  unindexed/subdir-only file relies on the agent grepping to discover it (~75%).
- **Both** the root one-liner **and** the per-file frontmatter `description`
  feed CC's selection classifier — each an independent lever (U1) — but only the
  always-loaded index line is *reliably* recall-reachable.

Consequence: a tier's facts become reliably recall-reachable
**iff their pointers appear in the root `MEMORY.md`**, regardless of where the
bodies physically live.

**Two surfaces, bidirectional drift — the index line is canonical.** A memory
file carries its pointer text twice: the root `MEMORY.md` one-liner and the
frontmatter `description`. These **drift apart bidirectionally** — the agent
only ever has the root index loaded, so it revises whichever surface it is
looking at and the other goes stale, in *both* directions (evidence, from a
git-history audit of this repo's own memory:
`feedback_memory_retrieval_in_practice` kept a fresh index line over stale
frontmatter; `reference_git_hook_env_leak` was the reverse — corrected
frontmatter/body, stale index line). Neither surface is a reliable single source
of truth, and judging which of two divergent texts is fresher is a *semantic*
call, not a string op. So the **root index one-liner is treated as canonical** —
agent-curated, always-loaded, and the reliable retrieval lever; the frontmatter
`description` is a secondary, weaker match-surface.
**No mechanism derives the index text from frontmatter** — deriving it would
clobber curated lines and re-inject stale text
([index-authoring-sync.md](index-authoring-sync.md)'s Rejected
alternatives).

**D27 — Tiers materialize as nested submodules, discovered by enclosure**

Each tier is a git submodule mounted *inside* the project's memory submodule at
a free-form path (`memory/ddaanet`, …). It reuses the existing init, FR11 commit
gate, and push-lockstep machinery — a submodule-within-a-submodule, more nesting
of an already-solved problem (D11/D12 carry the linked-worktree and hook-env
scar tissue). Discovery is by **enclosure, not name**, and the asymmetry with
the parent level is load-bearing: the parent picks *one* submodule out of
possibly many by the fixed name `gitlore-memory` (the `GITLORE_SUBMODULE_NAME`
constant, resolved to a path through `.gitmodules`), so a repo's unrelated
submodules stay foreign; but a submodule nested *inside the memory store* is a
tier *by definition* — `SessionStart` enumerates the memory submodule's own
`memory/.gitmodules` and treats every entry as a tier. No tier-name constant
exists, nor should one: at the memory level the enclosure is the signal, which
is why "don't hardcode the tier name" falls out for free. The first concrete
tier is org-scoped `ddaanet`; a truly-global tier waits until there is anyone to
share it with.

**D28 — Routing is a generation choice, not a content classifier**

Which tier a new fact belongs to is a *generation* choice the authoring agent
owns, guided by the standing SessionStart `additionalContext` (the D12
orientation block): portable facts → the appropriate `memory/<tier>/`, project
facts → `memory/`. The directory *is* the tier *is* the submodule, so the FR11
gate commits whichever submodule the file landed in, and no shell logic inspects
a fact's content to route it. D7 governs *detection*, and where to file a fact
you are already authoring is not detection.
**The per-tier routing guidance is self-describing and travels:** each tier
states what it is for in its own `memory/<tier>/MEMORY.md` frontmatter
`description:`, authored once by whoever owns the tier and identical in every
consuming repo — the DRY a per-consumer routing manifest would break — and
`SessionStart` reports the *active* tiers' descriptions into
`additionalContext`. Composition only ever moves `- […]` pointer lines, so this
frontmatter is never spliced: "what the tier is for" is intrinsic and travels,
"which tiers are active here and in what order" is the local manifest. The
guidance rides `additionalContext`, model-only per D14 and observed not to
inject under `--print`, so a missed guidance misfiles a global fact into the
project tier — self-correctable, never corruption.
**D32 — Mount and create converge, and both activate as their own last step**

**Mount** (common — a repo joins an existing tier):
`git submodule add <url> memory/<name>`. **Create** (rare — the first repo
stands up `ddaanet`): init an empty module, seed its `MEMORY.md` + frontmatter
`description:`, create and push its remote, *then* take the identical mount
path. The window where the module exists but does not yet self-describe is
unobservable outside the script, since both modes converge before either commits
to the manifest. `/gitlore:add-tier` performs the mount, with a `mode=create`
path for the creation flow. It routes its git through the same trigger-file
pattern as the FR11 commit path — the agent writes `.claude/gitlore-add-tier`
(`key=value` lines: `mode`, `name`, `url`, `description`) and a `PostToolBatch`
hook runs `scripts/add-tier.sh` on its behalf. Two independent reasons the agent
cannot run it itself: the auto-mode classifier reads a submodule mutation as
self-modification, **and** mounting clones while the agent's command sandbox has
no network — a hook runs outside both. The intent is one-shot (consumed whether
it succeeds or fails), because an add-tier failure is a bad url or a taken name,
not a transient lock worth retrying. Because the hook has network and no
sandbox, the url is bounded to a scheme allowlist before git sees it — the
`helper::address` transport form (`ext::`, which runs a shell command) is
refused outright rather than left to git's `protocol.ext.allow` default.

Both modes end by **appending `name` to `memory/.gitlore-tiers`** — activating
the tier at the bottom, the lowest precedence, the position that cannot outrank
a tier this repo already trusts, and reorderable by hand afterwards. Neither
mode commits inside memory: `gitlore_tier_paths` reads `memory/.gitmodules` from
the working tree, so a staged `submodule add` is already discoverable and the
FR11 gate stays the sole committer — the manifest write is the same kind of
working-tree-only edit. `add-tier-batch.sh` calls `gitlore_compose_and_report`
directly on a successful mount, folding the recompose and the post-mount triage
nudge into the one JSON response it emits, then drops the compose stamp so the
same manifest change is not reported twice in one batch.

**D33 — A tier may carry always-on conventions, and the mount reports the import
line rather than writing it**

A rule that must act without being looked up has no lookup step for an index
pointer to serve, so it belongs in a file that loads whole every session rather
than behind a routing line — for a tier, `shared-claude.md` at the tier root,
imported by each consuming repo as `@memory/<tier>/shared-claude.md` in its own
`CLAUDE.md`. The name is deliberately not `CLAUDE.md`: a file by that name
inside the store would be injected whenever an agent touches the memory
directory, which is not a place conventions apply, and it would collide with the
consuming repo's own root file. Nothing loads it until the consumer imports it,
and an `@` import naming a path that does not exist is silent — so `add-tier.sh`
reports the exact line only once the mounted tier actually carries the file, and
stays quiet when `CLAUDE.md` already has it. The append itself stays with the
agent rather than the script, because the same pass has to read the imported
file and drop the rules the repo's own `CLAUDE.md` now duplicates — the shared
file occupies the scope between a repo's `CLAUDE.md` and the user's
`~/.claude/CLAUDE.md` — and that is judgement, not detection.

## Rejected alternatives

**A flat merge-everything store** (one shared directory for all repos). Blows
the always-loaded root-index budget and loads N irrelevant projects' facts every
session. Recall is on-demand, so a large tier is free *if* it is surfaced by
selection — tiered composition keeps bodies on-demand and splices only pointers
into the root index (D29).

**A content classifier routing each new fact to global-vs-project.** Puts model
reasoning on the write path to inspect a fact's content. Where to file a fact
you are already authoring is a generation choice: the agent picks the directory,
the directory is the submodule (D28).
