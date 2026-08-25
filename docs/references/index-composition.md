# Index composition — decisions D29–D31, D34–D37

How a repo's root memory index comes to hold every active tier's pointer lines
alongside its own, and what keeps the two surfaces from fighting. One of the
four nodes of the tiered-memory subsystem (FR15), whose entry point is
[tiered-memory.md](tiered-memory.md).

- Composition — **D29** composition is placement, never text-derivation ·
  **D30** the tier manifest is the activation and precedence surface · **D31**
  compose triggers and validation · **D34** the index is authoritative over a
  pointer line's presence · **D35** the welded-line refusal · **D36**
  composition is two projections · **D37** index order is a merge input

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

Composition runs at three points. At `SessionStart`, after the tier
fast-forward, to surface propagated lines. Mid-session on
**`PostToolBatch` when the root index or `memory/.gitlore-tiers` is written**,
so the agent can edit the manifest, see the regenerated index, and adjust
ordering within one session. And in the
**merge continuation, before it commits**: a merge synthesizes an index outside
any tool edit, the one write path the other two triggers cannot see, and
composing there puts the composed bytes in the merge commit itself rather than
in a later, unrelated one. That pass is **up-only** (Rejected alternatives,
below).

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

## Rejected alternatives

**Propagating the root index down into the carriers during the merge
continuation.** The adoption there is up-only, for two independently sufficient
reasons: the merged tier's facts must reach the root because that is the only
surface recall reads, and projecting down writes a second store the user never
reviewed as a side effect of approving one index. In-session propagation is the
hooks' job (D36).

**Recompose owning index-line presence — coverage (seed a missing pointer from
frontmatter) and prune (drop a bullet whose file is gone).** Both are refused by
the presence-authority rule: the index is authoritative over a line's presence,
and no surface is auto-edited to match the other. Coverage resurrects a line the
user deliberately removed; prune inverts the authority and destroys what may be
the last trace of a lost memory. Each also hardcodes a semantic call — was this
deletion deliberate? — that belongs to the agent (D34).

**Deleting a memory file when its pointer line is removed.** Prune's mirror
image, refused for the same reason index authority is non-destructive: a
destructive edit as the silent consequence of an index edit is the one surprise
a memory store must not spring, and the file is the only place the fact still
lives. Unlisting a fact and destroying it are different acts (D34).

**A `SessionStart` warning when a tier is mounted without a paired guard
plugin.** gitlore models no dependency from a memory tier to any plugin, and
inventing one would be wrong in the general case: prohibitions are per-project,
each repo carrying the set its own work needs, so a tier mount is no evidence
about which guards that repo should have. The warning would also make gitlore
the enforcement point for a second plugin's installation, reading
`enabledPlugins` — a record of what the user chose — as a defect report.
