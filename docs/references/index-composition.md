# Index composition — decisions D29–D31, D36, D37

How a repo's root memory index comes to hold every active tier's pointer lines
alongside its own, and what keeps the two surfaces from fighting. A node of the
tiered-memory subsystem (FR15), whose entry point is
[tiered-memory.md](tiered-memory.md). What composition reports (D34, D35, D57)
is in [composition-reports.md](composition-reports.md).

- Composition — **D29** composition is placement, never text-derivation ·
  **D30** the tier manifest is the activation and precedence surface · **D31**
  compose triggers and validation · **D36** composition is two projections ·
  **D37** index order is a merge input

---

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

Composition runs at two points, and only where an edit happens (D74).
Mid-session on **`PostToolBatch` when the root index, `memory/.gitlore-tiers` or
an active tier's carrier is written**, so the agent can edit the manifest, see
the regenerated index, and adjust ordering within one session. And in the
**merge continuation, before it commits**: a merge synthesizes an index outside
any tool edit, the one write path the session triggers cannot see, and composing
there puts the composed bytes in the merge commit itself rather than in a later,
unrelated one. That pass is **up-only** (Rejected alternatives, below). The
mount composes too, by calling the batch's reporting function directly.
`SessionStart` and the commit path compose nothing: an index that is off there
changed outside a batch, and is reported (D74, [session.md](session.md)) or
aborts the commit (D50, [git-hooks.md](git-hooks.md)), and `gitlore-compose`
clears it.

The mid-session trigger keys on
**what changed, not on what the batch declared**: `index-sync-pre.sh` stamps the
root index, the manifest and each active tier's carrier before the call (a tier
with a prepared merge is left out), and `index-compose.sh` composes at batch end
if any of those stamps moved. A tool call is a poor proxy in both directions —
an `Edit` can rewrite a line to itself, and a `sed -i` under `Bash` never names
its target at all, which is why the `PreToolUse` matcher is `Write|Edit|Bash`
and a Bash call takes the baseline unconditionally. Two paths reach the same
`gitlore_compose_and_report` call: that stamp comparison, and
`/gitlore:add-tier`'s mount, where `add-tier.sh` calls the function directly
right after a successful mount. The mount runs inside a Bash call, so the stamp
comparison would catch it too: `add-tier.sh` then moves the baselines its own
batch took to the post-mount state, so `index-compose.sh` does not report the
mount a second time.

The recompose **validates and is fail-safe**: it refuses — reporting on
`systemMessage` (user) + `additionalContext` (agent) without clobbering the
existing index — if the result would carry a **duplicate** pointer line, if a
line **welds two pointer bullets** onto one physical line, if the manifest
**lists a tier that is not present**, or if an
**active tier is checked out off the gitlink** the memory store's index records
for it. That last rule guards the down projection alone (D36), so it lives
outside the shared check and only the down-projecting passes run it:
`gitlore_compose` itself, so every compose on `PostToolBatch` and after a tier
mount, and the commit path, which also checks it ahead of its read-only pass so
an off-pin tier aborts the commit (D50). The merge continuation's adoption is
up-only and runs while the tier is legitimately ahead of the pin, before that
path stages the moved gitlink. The pin is read from the memory store's **index**
rather than its `HEAD`, because the index is what `submodule update` checks a
tier out at and what every advancing path stages the move into (D43) — a landed
merge is not a defect for as long as the memory commit recording it is pending.
A tier that is mid-merge gets the remedy its own state needs,
`/gitlore:resolve`, rather than the return-to-the-pin checkout, which would
unlink `MERGE_HEAD` and destroy the prepared merge. A tier merely ahead of its
pin — clean, its local `live` holding every commit its `HEAD` does — is checked
out at the pin and sent to `/gitlore:merge`, which adopts from `live`
([git-hooks.md](git-hooks.md)). A mounted tier *absent* from the manifest is not
an error, only inactive; the asymmetry is deliberate — listed-but-absent =
broken, present-but-unlisted = dormant. In the continuation, a problem in the
merged index itself blocks the landing — in the tier's carrier for a tier merge,
and a duplicate, interleaved or welded line in root's `MEMORY.md` for a
memory-root merge. Nothing is committed, the merge stays prepared, and the
merger re-synthesizes with the problem lines in hand: the defect is in text this
repo is authoring, and an edit to the named lines clears it (D52, in
[tier-arrival-repair.md](tier-arrival-repair.md)). Any other refusal is reported
and does not block, because the merge is synthesized and approved by then, and
stranding it over a problem outside what it merged is the worse outcome. A
memory-root merge then commits uncomposed and says so; a tier merge lands in the
tier, which rests on its pin unadopted (D43).

**A store with no root `MEMORY.md` composes nothing and is checked by nothing,
and says so once an episode.** Every pass keys on that file, so its absence
turns off the projection, the four validations, the weld rule and the merged
index gate at once, and Claude Code loads no memory index either — all of it
silently. `SessionStart` writes the `# Memory Index` scaffold back, so a store
reaching a batch without one lost the file inside the session;
`index-compose.sh` reports it on both channels in place of composing, keyed by
session like the byte-budget and plugin-upgrade notices, and re-armed at
`SessionStart(startup|clear|compact)` by `nudge-reset.sh`. The notice reports
and never repairs: a file the hook wrote would enter the store outside the
approval gate that accounts for everything else in it. Install owes the same
scaffold — including to an auto-memory dir migrated with facts and no index
([installation.md](installation.md)).

Composition spans the whole memory tree, so from the continuation it can also
write a store *other* than the one being committed — the root index when a tier
merged, a carrier when memory did. Those writes stay dirty and ride the next
FR11 commit.

**The `Bash` arm is measured, not assumed**: ~45 ms on every shell call buys the
memory mutations no `Write|Edit` matcher can see — a `git checkout` names no
`file_path` — and is accepted because the failure it prevents is silent. The
corpus measurement and the timing are in
[compose-bash-arm.md](compose-bash-arm.md).

**D36 — Composition is two projections; the three-way lives in the merge**

The root's tier block and the carrier are two projections of the same facts, and
under a pinned tier only one of them can move between passes: the agent edits
the root, and the carrier changes only when a merge lands a new commit. So
composition needs no base and no merge of its own. The pin is a
**precondition, not an assumption** — a tier moved outside `/gitlore:merge` has
a carrier nothing adopted up, and projecting root's older text down over it
destroys approved upstream facts while reporting a successful compose, so the
down pass refuses onto a tier that is off its pin (D31). It runs two projections
instead:

- **Down**, on `PostToolBatch` and at the mount: root's lines for each ACTIVE
  tier are written into that tier's carrier, de-prefixed, with root's text and
  root's order. Root is canonical, so this is what carries a locally-authored
  line into the store that travels.
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

**A line only the carrier lost is root's, and comes back.** A carrier path root
lacks is a deletion only when root made it. The converse — root still carries
the path and the carrier does not — means the carrier alone lost the line,
whatever root at `HEAD` says: root is canonical, so the line is root's insertion
and is written at root's offset with root's text. A removal therefore starts in
the root index. The batch reports the restored path and says so, because the
files show no trace of the pass; a tier holding a prepared merge is not watched,
since the merger edits its carrier and the pin rule would refuse every batch.

**A path that arrived from upstream reaches `HEAD` only with the recompose that
took it.** The up projection writes root's block from the merged carrier as an
ordinary working-tree write, and what commits it is the take's own bookkeeping,
which an explicit take records on a store that was clean before it (D49, in
[merge-and-resolve.md](merge-and-resolve.md)); a take on a dirty store stages
the pair instead, and a landed merge's compose leaves its write for the next
FR11 commit. Until one of those lands, the arrived path is absent from root at
`HEAD`, so the lookup reads it as one nobody authored in root — removing the
line from the root index propagates nothing, and the carrier's copy goes in the
same change or stays, reported as in the tier but not in the root index, and
travels to every consumer of that tier. Root at `HEAD` is therefore what says
whether a pointer removal is one edit or two.

**Root with no line at all for an active tier states nothing about it**, so both
halves defer: the down projection skips the tier entirely, and the layout adopts
its carrier. That single rule covers a freshly mounted tier (the augmentation a
mount owes the root index), a deactivate/reactivate round trip, and a tier whose
block the agent cleared — the way to drop a tier's facts from a repo is to
deactivate it, not to empty its block.

**Removing a tier pointer is one of three edits, and the dangling and orphan
reports name which**, decided by root at `HEAD` and root's other lines for the
tier; the recipe is in [index-drift-fixes.md](index-drift-fixes.md).

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

## Rejected alternatives

**Propagating the root index down into the carriers during the merge
continuation.** The adoption there is up-only, for two independently sufficient
reasons: the merged tier's facts must reach the root because that is the only
surface recall reads, and projecting down writes a second store the user never
reviewed as a side effect of approving one index. In-session propagation is the
hooks' job (D36).

**A `SessionStart` warning when a tier is mounted without a paired guard
plugin.** gitlore models no dependency from a memory tier to any plugin, and
inventing one would be wrong in the general case: prohibitions are per-project,
each repo carrying the set its own work needs, so a tier mount is no evidence
about which guards that repo should have. The warning would also make gitlore
the enforcement point for a second plugin's installation, reading
`enabledPlugins` — a record of what the user chose — as a defect report.
