# Tiered memory — decisions D17, D26–D40, D42–D44

Full decision set for FR15 (tiered memory) — the mechanism `design.md`'s D17
points at. Motivation, FR15 itself, and the Architecture overview stay in
`design.md`; this file is the decision-level detail, split out because the
cluster runs to ~47 KB, on par with every other decision in the graph combined.
Most of it is needed only when touching this subsystem; the exception is the
tier-store trio D42–D44, which the commit and merge paths reach from outside it.

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
recorded individually as **D26–D40 and D42–D44**:

- Retrieval and routing — **D26** the root index one-liner is canonical ·
  **D27** materialization by enclosure · **D28** routing without a content
  classifier · **D32** mount and create · **D33** a tier's always-on conventions
- Composition — **D29** composition is placement · **D30** the tier manifest ·
  **D31** compose triggers and validation · **D34** presence authority · **D35**
  the welded-line refusal · **D36** two projections · **D37** order as a merge
  input
- The authoring surface — **D38** the one-way sync · **D39** the routing-key
  advisories · **D40** pre-existing drift
- Stores and merges — **D42** tier lockstep · **D43** tier pinning · **D44**
  tier merges. All three assume the detached-at-`live` branch model, which is
  D41, in [merge-and-resolve.md](merge-and-resolve.md).

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
clobber curated lines and re-inject stale text (design.md's Rejected
Alternatives).

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

**D29 — Index composition is placement, never text-derivation and never
hygiene**

The composition owns a *tier* line's presence and placement *in the root index*,
never its text and never the project's own lines. It reconciles two surfaces per
active tier by **line identity = path prefix** — no sentinel text is ever
injected into either index: a root-index pointer whose path begins with an
active tier's mount dir (`ddaanet/…`) is that tier's line; a bare path
(`project_overview.md`) is a local/project line. Both projections
**rewrite the prefix** — down, each root tier line lands in the carrier
prefix-stripped, so a locally-authored line travels with the tier submodule into
every consuming repo; up, each carrier line lands in the root prefix-added
(`- [T](foo.md)` in `memory/ddaanet/MEMORY.md` → `- [T](ddaanet/foo.md)` in the
root, so the always-loaded Read resolves to `memory/ddaanet/foo.md`). The
composed root index is `[tier blocks, in manifest order] → [project lines]`:
tier blocks ordered by the manifest, each preserving its carrier's own line
order; project bare-path lines last, in the order CC arranged them (composition
never reorders or touches them). It is **idempotent** — an already-canonical
index rewrites to identical bytes, so no spurious churn. The carrier is *not*
consulted by CC for recall, only the root being always-loaded; it exists as the
tier's canonical, travelling store, and composition is what surfaces it.
Deactivating a tier drops its block from the root on the next compose; the lines
persist in the carrier. The two writers of the root `MEMORY.md` are disjoint by
*aspect*: the agent — and CC's native pointer-writing — owns each line's text
and its creation and deletion, composition owns tier-block placement.

**D30 — The tier manifest is the activation and precedence surface, never
inferred from bare presence**

Composition, routing-advertising and ordering are all keyed on one
consumer-local file, `memory/.gitlore-tiers` (tracked in the memory submodule,
one tier path per line, top = highest precedence). It is the single
**activation** surface: *listed = active*. A tier can be mounted yet
**inactive** — a first-class, harmless state. The manifest gates three things
uniformly: only listed tiers splice into the root index, only listed tiers are
advertised for routing, and their listing order is their precedence. Ordering
lives here rather than in `.gitmodules` (whose section order is incidental
add-order, rewritten by git porcelain) or in the index (which CC rewrites freely
and must carry no marker text) — an explicit, git-porcelain-untouched container,
consumer-local because precedence is a per-repo choice. The manifest is
**never populated from `SessionStart`'s passive discovery-by-enclosure**:
enumerating whatever submodules happen to exist under `memory/` must not imply
activation, since a stray or manually-mounted submodule could exist for
unrelated reasons, and a half-formed one — still mid-creation, before it
self-describes — must stay invisible to composition. `/gitlore:add-tier` is not
passive, running only because the agent explicitly named *this exact tier*, so
it activates as its own last mechanical step: appended at the bottom, the lowest
precedence and least surprising default. Reordering, or listing a tier mounted
by hand, stays a deliberate manual edit.

**D31 — Compose triggers and validation**

Composition runs at three points. At `SessionStart`, after the tier
fast-forward, to surface propagated lines. Mid-session on
**`PostToolBatch` when the root index or `memory/.gitlore-tiers` is written**,
so the agent can edit the manifest, see the regenerated index, and adjust
ordering within one session. And in the
**merge continuation, before it commits**: a merge synthesizes an index outside
any tool edit, the one write path the other two triggers cannot see, and
composing there puts the composed bytes in the merge commit itself rather than
in a later, unrelated one. That pass is **up-only** (design.md's Rejected
Alternatives).

The mid-session trigger keys on
**what changed, not on what the batch declared**: `index-sync-pre.sh` stamps the
root index and the manifest before the call, and `index-compose.sh` composes at
batch end if either stamp moved. A tool call is a poor proxy in both directions
— an `Edit` can rewrite a line to itself, and a `sed -i` under `Bash` never
names its target at all, which is why the `PreToolUse` matcher is
`Write|Edit|Bash` and a Bash call takes the baseline unconditionally. Two paths
reach the same `gitlore_compose_and_report` call: that stamp comparison, and
`/gitlore:add-tier`'s activation write, which happens inside `add-tier.sh` after
the baseline was taken and so cannot be attributed to a tool call —
`add-tier-batch.sh` calls the function directly, in the same batch, right after
a successful mount.

The recompose **validates and is fail-safe**: it refuses — reporting on
`systemMessage` (user) + `additionalContext` (agent) without clobbering the
existing index — if the result would carry a **duplicate** pointer line, if a
line **welds two pointer bullets** onto one physical line, or if the manifest
**lists a tier that is not present**. A mounted tier *absent* from the manifest
is not an error, only inactive; the asymmetry is deliberate —
listed-but-absent = broken, present-but-unlisted = dormant. In the continuation
a refusal is reported but never blocks: the merge is synthesized and approved by
then, and stranding it half-landed over an index problem the agent fixes in one
edit is the worse outcome, so the merge commits uncomposed and says so.
Composition spans the whole memory tree, so from the continuation it can also
write a store *other* than the one being committed — the root index when a tier
merged, a carrier when memory did. Those writes stay dirty and ride the next
FR11 commit, the same float the `SessionStart` recompose produces.

**The `Bash` arm is measured, not assumed**. Watching `Bash` widens the
`PreToolUse` matcher from calls that name a memory file to every shell call, so
the trade was settled against this machine's own transcript corpus — 2,441
transcripts, 22,168 `Bash` calls, 13 months. Of those, ~49 mutated a real memory
store: ~22 touched an index, ~29 a fact file, the sets overlapping. All but one
fall in the corpus's final five weeks, so the behaviour is rising rather than a
long-tail artifact — the arm earns more, not less, as the store ages. Fifteen
were `git checkout`/`git restore` and three `git rm` — write paths that name no
`file_path` at all, so no `Write|Edit` matcher can see them however it is
scoped, which is the part of the case that cannot be met another way. Against
1,190 `Write`/`Edit` calls on memory files, the arm exists for roughly 4% of the
mutations and ~0.2% of the `Bash` calls it inspects. Of 25 native auto-memory
stores under `~/.claude/projects/*/memory`, exactly one was ever mutated from
`Bash` across the whole corpus: shell mutation is a *gitlore*-store phenomenon,
because a gitlore store is a git repo the agent already runs git against. Cost,
timed against this repo's real tree (23 KB index, one tier, 30–50 runs per path,
steady state): **~45 ms** on a `Bash` call once the batch has a baseline,
**~65 ms** on the first watched call of a batch (two `cksum`s plus the index
`cp`), against ~18 ms for the bare unwatched-tool exit; a cold page cache
roughly doubles all three. That is ~45 ms on every shell call to catch a
mutation in one call out of five hundred. Accepted, because the failure it
prevents is silent — the edit lands, neither propagation nor composition runs,
and the store desyncs with nothing to show for it — and 45 ms is invisible next
to a tool call's own latency.

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

**D34 — The index is authoritative over a pointer line's presence, and nothing
is deleted to enforce it**

The index is what memory *contains*: a file on disk with no pointer line is not
part of memory, and a line is added or removed only by the agent, deliberately.
Authority here is a reading rule, not a licence to make one surface match the
other — in particular, removing a line never deletes the file it named. A
destructive edit as the silent consequence of an index edit is exactly the
surprise a memory store must not spring, and the file is the only place the fact
still lives. Composition may *report* a mismatch; it never repairs one.

*This settles coverage, prune, and dedup — all three stay out.* **Coverage**
(reconstruct a missing pointer line from a file's frontmatter) contradicts the
rule outright: an unlisted file is unlisted on purpose, and seeding a line would
resurrect one the user removed. **Prune** (delete a bullet whose file is gone)
inverts the rule, letting the file set decide presence; under index authority
the line is the record and the *missing file* is the anomaly, so dropping the
line silently destroys what may be the last recoverable trace of a lost memory.
Both also hardcode a semantic call — was this deletion deliberate? — that
belongs to the agent. The rule is that *file presence* never drives a line's
deletion; how a *tier* line's presence is reconciled between the root and
carrier indexes is a separate question, settled by the two projections below
(D36). **Dedup** falls on independent grounds: it guarded duplicate path lines
from a `merge=union` driver that is not used (D44), and distinct per-index
namespaces make cross-index duplication impossible, so it guards nothing
anywhere in the system.

What the rule *does* leave open is a non-destructive **dangling-pointer report**
— a fifth compose validation naming any bullet whose target file is absent. It
reports and does not refuse: unlike the other four, a dangling line does not
make the composed output wrong, and refusing the pass would block every later
write over a stale line the agent fixes in one edit. That makes it a
*separate pass* (`gitlore_compose_dangling`) which every compose trigger calls
after `gitlore_compose` returns, rather than a rule inside
`gitlore_compose_check`, whose contract is "refuse and write nothing" while
compose's return value stays a list of what it *wrote*. It runs on the composed
store and speaks whether or not anything was written, so a stale line surfaces
on the next index edit even when composition was idempotent. It scans each
mounted tier's carrier as well as the root: a **dormant** tier's bullets never
reach the root, so a root-only scan would leave them unchecked for as long as
the tier sleeps. A line present in both indexes resolves to one file and is
reported once, against the root — the surface the agent has loaded and edits.

**D35 — A welded index line is refused on both surfaces**

Two pointer bullets joined onto one physical line parse as *one* valid bullet
for the first path, so the duplicate and interleaved rules see nothing and the
second path is absent from every parse of the index — which the next composition
reads as a root-side delete and drops from the carrier, losing the entry. The
rule (`gitlore_welded_path`) keys on the first link's closing paren rather than
on the `) — ` separator, so glue landing ahead of the first hook is caught too,
and it carries **no backtick-awareness**: a hook has no legitimate use for a
bare markdown hyperlink, since the entry already links its own file, so the
pattern is safe by policy rather than by parsing. The accepted residual is a
hook quoting an index-format example, reported spuriously and repaired in one
edit; a balanced-span pattern was rejected because awk has no backreferences and
POSIX leaves them undefined in EREs, so it would force the check out of the
idiom the rest of the index parsing uses to buy what the policy already gives.
The authoring-time sync refuses the same shape independently:
`gitlore_index_pairs` splits on the first `) — `, so a welded line yields one
syntactically valid pair whose *hook* contains a whole second bullet, and
propagating it faithfully would move the corruption from the index — where a
compose check and a human both look — into a `description:` where neither does.
That refusal names its files on the user's channel as a failed write does,
because it needs action. Both are containment for the Claude Code `Edit` weld
defect (design.md's D23), not a fix. Detection belongs in the stateless pattern
check over the root *and* the carriers rather than in a preimage diff, because
`index-sync-pre.sh` takes a baseline only for the root index and the tier
manifest — a carrier has none, and hand-editing a carrier is a documented
requirement when a pointer arrives from upstream in a merge.

**D36 — Composition is two projections; the three-way lives in the merge**

The root's tier block and the carrier are two projections of the same facts, and
under a pinned tier only one of them can move between passes: the agent edits
the root, and the carrier changes only when a merge lands a new commit. So
composition needs no base and no merge of its own. It runs two projections
instead:

- **Down**, in-session, on `PostToolBatch` and at `SessionStart`: root's lines
  for each ACTIVE tier are written into that tier's carrier, de-prefixed, with
  root's text and root's order. Root is canonical, so this is what carries a
  locally-authored line into the store that travels.
- **Up**, once, at the tier-adoption step of a landed merge: the merged carrier
  becomes root's block for that tier. This is the one moment a carrier outranks
  root's text — it is the artifact the user just approved, line by line — and it
  is the only thing that makes a merged tier fact reachable, since the root
  index is the only surface CC recalls from.

Alongside the down projection the same pass rewrites root's **layout**: active
tier blocks in manifest order, then the project's own lines. A reorder, so the
in-session pass still never changes a line's text.

**One lookup disambiguates a deletion.** A carrier path root's working tree does
not carry is either a line root deleted or one root never had, and the working
tree alone cannot tell them apart. Root **at `HEAD`** answers it: present there
→ root deleted it → the line goes; absent there → nobody authored it in root →
the line stays, and the pass names it in the report rather than resolving it,
because which surface is right is a judgement about the fact. The cost is that a
line added *and* deleted inside one uncommitted window reads as never-authored
and lingers in the carrier — reported, never silently destroyed. One `git show`
against a commit git already holds, and no reconciliation state that can outlive
what it describes.

**Root with no line at all for an active tier states nothing about it**, so both
halves defer: the down projection skips the tier entirely, and the layout adopts
its carrier. That single rule covers a freshly mounted tier (the augmentation a
mount owes the root index), a deactivate/reactivate round trip, and a tier whose
block the agent cleared — the way to drop a tier's facts from a repo is to
deactivate it, not to empty its block.

**D37 — Index order is a merge input, not a rule applied afterwards**

Where a bullet sits in an index is an authored choice — the agent groups related
facts, puts the ones it wants seen first at the top — so both the root↔carrier
compose and the divergence merge merge the *order* as well as the presence,
through `gitlore_order_merge`: git's own three-way over the three
**path sequences**, with `--union` resolving a shared offset to ours-then-theirs
and the first occurrence of a repeated path winning. Each side's placements are
honoured, so an insertion keeps the offset its author gave it instead of being
appended to the block. Only a genuine disagreement about one offset falls back
to the rule, and it is never surfaced as a conflict: two sides inserting
*different* facts at one point disagree about placement, not about content, and
there is nothing for a human to adjudicate. The sequences are
**paths only, never bullet text** — feeding the lines in would make every
reworded hook a positional edit, so a routine description change would relocate
its entry and false-conflict against an unrelated insertion beside it. The down
projection takes the root as ours and the carrier as theirs, so root's ordering
propagates into the carrier, and a kept carrier-only line stays at the offset it
has there rather than collecting at the end. Ordering authority stops at the
tier block: composition still hoists each active tier's block above the
project's own lines, in manifest order.

**D38 — Authoring-time sync is one-way (index → frontmatter), because the index
is canonical**

A separate `PreToolUse(Write|Edit|Bash)` + `PostToolBatch` pair on the root
`MEMORY.md` mirrors an edited index one-liner's hook into the target file's
frontmatter `description` (after-the-dash hook → `description` only; never
`name`/title, which is the `[[wikilink]]` slug and file identity). One-way
because a bidirectional sync would resolve conflicts by tool-call order, and
since the file body is usually written after the index, the weaker frontmatter
would propagate *back* and clobber the curated index hook — the reliable
retrieval lever. Index hooks routinely carry content the frontmatter lacks:
measured 2026-07-16 over 528 transcripts across 8 projects, agents curate the
index one-liner over the `description` about 3:1. Letting frontmatter win a
conflict is therefore a silent downgrade.

`PreToolUse` captures the pre-edit index image so the post half acts
**per line, keyed by what changed against that image** — not a blanket sweep,
which would push an unrelated *stale* index line onto fresh frontmatter. A line
whose **hook changed** propagates, overwriting the `description`; a
**newly-added** line (absent from the pre-image) fills the `description`
*only when it is empty*, never clobbering a description authored alongside the
new file in the same batch; an **unchanged or merely reordered** line is a
no-op.

The post half runs on **`PostToolBatch`**, not `PostToolUse`, so a batch holding
several index edits syncs and reports once rather than per edit. A batch is one
assistant message's worth of calls, not a user turn — a single turn fires it as
many times as the agent takes batches (observed 2026-07-27) — so every baseline
is per-batch. It does not read `.tool_calls[]`: the stash the pre half left is
the whole signal, its presence saying a watched call ran this batch and `cmp`
against the file on disk saying whether that call moved anything, which is also
what covers a `Bash` call announcing no path. The first watched call of a batch
stashes and later ones must not re-stash (that would diff against a mid-batch
state and lose the earlier edits' changes); the post-hook drops the stash at
every batch end, even one where the index went untouched, so a pre-image can
never become a *second* batch's baseline. A stash stranded by an interrupted
batch is consumed rather than discarded: the difference between it and the file
is a propagation still owed. `PreToolBatch` would pair more neatly but is
unverified — absent from the hooks reference, with nothing observed confirming
it fires for a single call.

A frontmatter-only edit is left untouched; this hook never writes the index, and
it deploys globally through the plugin hooks. It is
**complementary to, not a substitute for, the structural recompose**: the sync
sees only in-session tool edits, so propagation arriving via `SessionStart` ff,
merges or `/gitlore:resolve` is invisible to it — precisely what the structural
pass covers.

**Both hooks are non-blocking but never silent**. Neither may ever `exit 2` —
the one code that blocks, and only at `PreToolUse`; at `PostToolUse` nothing can
block because the tool has already run. But `exit 0` is not licence to swallow
errors: a genuine failure (the stash `cp` fails; a frontmatter write fails)
reports on `systemMessage`, the D14 channel. Here `exit 0` is
*required for visibility rather than merely tolerated*, because
**stdout JSON is parsed only on exit 0** — a non-zero exit would discard the
`systemMessage` and make the error *less* visible. The post-hook checks each
`gitlore_set_frontmatter_description` explicitly (an `if !` condition, which
suspends `errexit`) so one bad target cannot abort the loop and strand the rest,
and consumes the stash **unconditionally**: a surviving pre-image is a hazard,
since a later silently-failed `cp` would leave the next post-hook diffing a
fresh index against an ancient baseline and propagating wrong hooks. `|| true`
and a bare `|| exit 0` on a fallible command are rejected as dishonest error
paths.

**A routine sync reports on both channels, asymmetrically**. Propagation
overwrites an authored `description:` — the agent writes considered prose and
the canonical index hook replaces it — so the pass has to say so rather than
discard it silently. The two audiences want opposite volumes. The **user** gets
one line (`gitlore: reset frontmatter to match MEMORY.md (N files)`) plus
`suppressOutput` — the sync is routine and the before/after is noise; only a
*failure* names its file, because only a failure needs action. The **agent**
gets the full `old → new` list on `additionalContext`, plus the standing
direction that the rewrite is complete (do not re-read to verify) and that a
hook losing meaning is fixed **in the index line, not the file** — at the
explicitness required for compliance, every clause earns its place.

**D39 — Two routing-key advisories ride the same pass: byte budget and missing
trigger token**

The sync copies the index hook over the file's own `description:`, so both of
CC's match surfaces come from that one line — and a hook with nothing in it to
match on degrades both at once, silently. Two things about a line are countable,
and both **report and never refuse**, the asymmetry the dangling-pointer report
settled: `PostToolBatch` cannot undo the write, and a thin hook is a quality
regression rather than corruption.

The first is the **byte budget**. The index blob is loaded verbatim into every
session, so cost is bytes, not lines, and the longest entries are where curation
pays — measured here, the five longest lines are ~a fifth of the whole blob
while every terse behavioural line together is a rounding error. Past
`GITLORE_INDEX_BUDGET_WARN_PCT` (80) of `GITLORE_INDEX_BUDGET_BYTES` (25600) the
pass names the percentage and the five largest lines. It is arithmetic, so it
has no false positives.

The second flags a line **carrying no trigger token** — no path, flag, error
string, identifier, filename or version of the kind a future query would
contain. It is conditioned on the memory's `type`: a `reference` fact is reached
by the surface where you meet it, while a `feedback` rule is reached by topic
and is right to be prose. That gate is what makes it usable — measured over this
repo's 76 bullets, ungated it fires on 22, type-conditioned it fires on
**3 of 37** eligible lines, and all three are the ones worth rewriting.
Detection is word-at-a-time in awk rather than one ERE, because ERE word
boundaries are not portable (GNU `\b` vs BSD `[[:<:]]`) and splitting on
whitespace makes the boundary safe by construction — so `well-known` stays prose
while `--flag` is a flag. Both advisories are
**diff-keyed like the sync itself**: only lines this batch added or changed are
examined, or an old thin hook would re-report on every unrelated index edit. The
token check deliberately runs *before* the fill-if-empty bail, since a line
whose frontmatter the sync declines to touch is still the canonical routing key.

What neither can see is the third failure mode — a trigger that is
*present but buried* in a paragraph-length line. That is a semantic judgement,
left to the agent. A tf-idf-style score over the store's own bodies cannot
supply it either (design.md's Rejected Alternatives).

**D40 — Pre-existing index/frontmatter drift is a manual sweep, not a command**

The sync only pushes a *freshly edited* index line onto frontmatter; it never
fixes a **stale index** line, the harmful direction, because judging which of
two divergent texts is fresher is a semantic call rather than a string op.
Pre-existing drift therefore needs a manual sweep that picks the correct
one-liner per divergent file and writes it to the canonical index, frontmatter
following on that edit. It runs **after the sync is deployed** — reconciling
first, then editing without the sync in place, just re-drifts frontmatter. It is
per-project plus once per shared tier, and **opportunistic, not mandated**: the
index is the reliable lever, while stale frontmatter is low-harm and heals on
that line's next index edit. Non-gitlore CC-memory stores are out of scope.
**The sweep re-verifies against current reality rather than propagating
body→index.** Measured here (2026-07-17): of 60 index lines only 4 were
genuinely stale, and *two of those had stale bodies as well* — so "index stale ⇒
trust the body" is unsafe, because bodies rot too, especially platform- and
behaviour-dependent ones. A wrong *body* is fixed, along with any downstream
code or docs it seeded, not propagated. At 4 files no `/gitlore:reconcile`
command is warranted.

**D42 — Tier commit/push lockstep is driver-side, with one approval per
episode**

A tier commit rides the same before-and-alongside staircase the parent already
applies to memory, one level deeper: `gitlore_sync_tiers_to_live` commits every
dirty tier and advances its local `live` *before* memory's own `git add -A`, so
the moved gitlink is part of the memory commit rather than lagging it;
`pre-push` pushes each tier's `live` to its own remote *before* memory's, so the
pointer never goes out ahead of what it points at. Two decisions the shared
driver rests on:

*One approval summary per memory episode, not per tier.* The gate is keyed to a
single message file, and the episode's approved summary is reused verbatim as
the commit message in every store it touched. The user approves a set of
*writes*, not a set of repositories; N prompts for one decision buys no extra
information. What the approval prompt owes the user is
**grouping by destination** — a line bound for a shared tier is more public than
one bound for project memory, and that difference is the only part of the split
that carried real content.

*No recursing `pre-commit`/`pre-push` in the memory store.* Recursion is
driver-side, exactly as the parent already drives memory: the parent's hooks
call the sync function and push explicitly rather than relying on a hook one
level down. A hook-side version would re-litigate the full `--local-env-vars`
unset and the `GIT_INDEX_FILE` capture/restore at a level that needs neither,
and would force the FR11 gate to share `memory-pre-commit` with the driver — the
gate exits 0 on its first line under the blessed sentinel, so the two would
diverge by sentinel inside one hook. `memory-pre-commit` stays a pure gate and
is now *emitted into each tier as well*, since neither the parent's hooks nor
memory's own gate reach a submodule-inside-a-submodule; each tier gets its own
`gitlore.hooksDir` mirror because the wrapper's `git config` reads whichever
store it fires in.

Scope is every **mounted** tier, not only the active ones: the manifest governs
routing and composition, and silently dropping a dormant tier's writes would be
data loss rather than dormancy. Each loop guards `[ -e "$tierpath/.git" ]`
before any `git -C` — into an unchecked-out submodule that escapes to the
enclosing repo, which would have committed *memory* under the tier's name and
pushed memory's `live` to the tier's remote. Tier divergence surfaces at both
gates — the pending commit against the tier's local `live` (`head-vs-live`) and
local `live` against the tier's own remote (`head-vs-remote`) — is reported by
tier name with git's own reason, and resolves through the same merge path as
memory: each gate yields to `gitlore_yield_merge`, the state file names the
store the merge was prepared in, and the continuation finds it by walking the
stores (design.md's Workflows).

**D43 — A tier is pinned at its gitlink; advancing one is a merge**

SessionStart checks each tier out at the commit the memory tree records for it —
`submodule update --init`, on every session and not only when the tier was never
materialized, since a clone made before this model already sits ahead of its
gitlink and has to be put back — and nothing advances it silently. One memory
commit records the root `MEMORY.md` and the tier gitlink together, so root's
tier block and the carrier index it projects are consistent *by construction*; a
tier that fast-forwarded on its own leaves root describing one commit and the
carrier holding another, and nothing downstream repairs that — composition
places lines, it does not merge them. Taking an upstream commit is therefore a
merge, through `/gitlore:merge` or `/gitlore:push`.

**Taking is three cases, not one.** Both commands classify each store by
ancestry against the fetched `origin/live`. A remote already contained in `HEAD`
is nothing to take — local commits awaiting publication are the push's business,
and reporting them as waiting would send the user into a merge with nothing to
merge. A `HEAD` that is an ancestor of the remote is taken by
**fast-forward plus adoption**: the local `live` advances, the working tree
follows, and the arrived carrier is projected up into root's block for that
tier. No sub-agent — nothing is in dispute, and spending a synthesis on a
fast-forward would make taking upstream facts expensive enough to skip. Only a
genuine divergence prepares a merge and yields. A store with uncommitted changes
is refused rather than checked out over: the working tree may hold this
session's unapproved facts.

The tier fetch stays, **read-only**: `fetch origin live` with no refspec moves
no local branch, and its only job is to let SessionStart *name* a tier whose
remote is ahead or has diverged, by comparing `HEAD` and `FETCH_HEAD` for
ancestry. Ancestry rather than a refusal message, because a fetch that attempts
no ref update is refused for nothing — and ancestry is what distinguishes an
upstream arrival from local commits merely awaiting their lockstep push, which
must not be reported as waiting. A prepared merge is detected *before* anything
checks out: `git checkout`, which `submodule update` runs, unlinks `MERGE_HEAD`
and `MERGE_MSG` silently and on success, so a tier mid-merge is skipped entirely
and said so on both channels. A tier that arrived attached to a branch is
detached in place (no ref argument, so the commit does not move) — the branch
model has no working branch, and a commit made on one would advance a ref the
lockstep never reads.

The recomposition that follows leaves `memory/` **dirty — expected**, and it
rides the *next* parent commit like any other memory change. No scheduled
sync-commit and no FR11 churn: the gitlink pin floats, committing naturally with
the next parent commit rather than on a schedule of its own, which keeps the
reused submodule model intact.

**Dirty, but the moved gitlink is staged.** `submodule update` checks a tier out
at the sha the superproject's **index** holds, not the one its HEAD records, so
the unconditional pin and a floating gitlink are only compatible while the move
is in the index. Every path that advances a tier therefore stages the pair —
`MEMORY.md` and the tier — in the memory store as its last act: the
fast-forward-plus-adoption branch of `gitlore_merge_stores`, and the merge
continuation, which stages *after* its commit because the merge commit does not
exist before it. Left in the working tree alone, the move survives exactly until
the next `SessionStart`, which walks the tier back to the pre-merge commit while
the recomposed root index — an ordinary file write, not a gitlink — survives to
describe facts the carrier no longer holds. Nothing reports it: the command that
landed the merge exited 0, and the session that reverted it calls the tier
clean. Staging changes nothing about *what* is committed or when; it is what
makes the pin idempotent instead of destructive.

**D44 — Shared-tier conflicts resolve semantically; memory merges as prose,
indexes entry-wise**

Two repos inserting into a tier's `MEMORY.md` concurrently are resolved the same
way as any memory divergence — the semantic memory-merger sub-agent, which
merges both insertions without duplicating them. A `merge=union` driver is
deliberately *not* used: it concatenates blindly and would leave duplicate
pointer lines needing a cleanup pass. And because each index occupies a distinct
filename namespace — the root holds bare project paths, each tier carrier only
that tier's filenames — composed blocks never share a path across indexes
either. So no duplicate-pointer residue arises on any path and no dedup pass is
needed. No append-only constraint is imposed; conflicts are expected rare (the
more global a tier, the more stable it presumably is).

**Memory files merge as prose with a base section; index files merge as
entries.** `gitlore_prepare_merge` runs git's own three-way with
`merge.conflictStyle=diff3`, so every conflict the sub-agent reads carries the
`|||||||` base — which side *changed* a line is unknowable from two versions
alone, and that is precisely the judgement a semantic merge asks for. Index
files then go through a second, entry-wise pass (`scripts/lib/index-merge.sh`),
because an index is a list of records keyed by pointer path and a line-wise
merge reads it as prose. That misreading fails in both directions: two sides
inserting **different** facts at the same offset conflict textually although
nothing is in dispute, and two sides inserting the **same path** at different
offsets do not conflict at all and yield a duplicate pointer — the state
`gitlore_compose_check` refuses on, so the silent textual success is what
strands the store. The entry-wise pass keys on the path and applies D34's
presence rule (at base → survives iff both keep it; new since base → survives if
either adds it), resolves text against the base, and emits a diff3 chunk only
for a path both sides moved apart. It runs on **every** index in the merge, not
only the ones git flagged, since the duplicate arises from a merge git considers
clean; a side that already names one path twice is *declined* rather than
collapsed, leaving the malformed index for `gitlore_compose_check` to report.
Because the pass resolves an index in the worktree without staging it,
`conflicted_files` in the state file is the union of git's unmerged entries and
`gitlore_conflicted_indexes`. Its chunks carry **git's own labels** — `HEAD` for
the authoritative side (checked out detached by the prepare) and the incoming
commit's sha — rather than a vocabulary of gitlore's own, so one merge never
presents the sub-agent with two namings of the same two sides. That is one
argument at the call site, against a sentence in `agents/memory-merger.md`
reconciling the two: a configuration that removes the need for agent-facing
prose beats the prose.

**The merger sub-agent is briefed with both side diffs and the tree.** Alongside
the state file, `gitlore_prepare_merge` writes three read-only artifacts into
the store's gitdir — `gitlore-merge-mine.diff` (base→authority),
`gitlore-merge-theirs.diff` (base→pending) and `gitlore-merge-tree` (`ls-files`)
— named in the state file as `mine_diff`, `theirs_diff` and `tree`. The merged
worktree shows the outcome but not the intent, and re-deriving the intent is
work the sub-agent would otherwise do with git commands it should not be
running. `gitlore_clear_merge_state` is the single remover for the state file
and all three, so a briefing cannot outlive its merge and be read against the
next one. **`No conflict.` is an explicit valid answer** for the sub-agent:
divergence is a git fact, not a semantic one, and a merge whose two sides say
compatible things is the common case. It is a finding to check, not an admission
that the work was skipped — the agent still reads both diffs and the changed
files, still runs `git add -A`, and still stops for approval.
