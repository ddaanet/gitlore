# Composition reports — decisions D34, D35, D57

What composition prints, and what a reader holding one of its reports needs to
know: the dangling-pointer report and the rule that no surface is edited to
match the other (D34), the refusal of a welded line (D35), and the size line the
mount ends with (D57). A node of the tiered-memory subsystem (FR15), whose entry
point is [tiered-memory.md](tiered-memory.md). The projections and triggers that
produce these reports are in
[index-composition.md](index-composition.md).

- Reports — **D34** the index is authoritative over a pointer line's presence ·
  **D35** the welded-line refusal · **D57** the mount reports its composed size
  against the loader cutoff

---

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
carrier indexes is a separate question, settled by the two projections in
[index-composition.md](index-composition.md) (D36). **Dedup** falls on
independent grounds: it guarded duplicate path lines from a `merge=union` driver
that is not used (D44), and distinct per-index namespaces make cross-index
duplication impossible, so it guards nothing anywhere in the system.

What the rule *does* leave open is a non-destructive **dangling-pointer report**
— a fifth compose validation, after the four in D31
([index-composition.md](index-composition.md)), naming any bullet whose target
file is absent, except a root line under a registered tier with no checkout,
which is not stale. It reports and does not refuse: unlike the other four, a
dangling line does not make the composed output wrong, and refusing the pass
would block every later write over a stale line the agent fixes in one edit.
That makes it a *separate pass* (`gitlore_compose_dangling`) which every compose
trigger calls after `gitlore_compose` returns, rather than a rule inside
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

**D57 — The mount reports its composed index size, measured against the loader
cutoff and keyed by nothing**

Mounting is the only operation that adds tens of KB of index in a single step,
and the only index-growing path that is not a `PostToolBatch` pass over an index
the agent edited — so D39's byte-budget advisory, which keys on that pass's
pre-image, never fires for it. Measured 2026-09-03: mounting `ddaanet` (91
facts) into a repo whose own index was the 48-byte scaffold produced a
25,846-byte `MEMORY.md`, past the loader cutoff, and the mount reported the
submodule, the tier's scopes, the import line, the activation and the
recomposition with no size line at all — that session learned its index was
truncating by measuring it by hand.

`gitlore_index_mount_size_line` closes it, and three things about it are the
decision. The measurement is taken **after** `add-tier.sh`'s own compose, never
before it: the mount appends a submodule and a manifest line, and it is
composition that splices the tier's pointer block into the root index, so a
count taken any earlier describes a file the session never loads. The loud arm
names the **cutoff, never the percentage** — the advisory budget (25,600) sits
*above* the cutoff (~24,985), so 100% of budget is already truncating and 97% of
it can be, which makes a percentage the reassuring number in the one case where
the mount has cost the repo its most specific memory. And the line is
**keyed by nothing**: `add-tier.sh` reports a mount once, when it composes, and
writing no `budget` marker leaves a later edit-time advisory in the same session
free to fire.

A mount past the cutoff is still a correct mount. This reports, never refuses —
an over-budget tier is its owner's to fix, not the consuming repo's — and the
one act it names is `/gitlore:index-audit`.

## Rejected alternatives

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

**Reporting the mount's size as a percentage of the advisory budget,** reusing
`gitlore_index_budget_pct` as the edit-time advisory does. The budget is the
wrong denominator on the one path that can cross the cutoff in a single step: it
sits above the cutoff, so the arm that must be loudest would print a figure
under 100% while the index truncates. The quiet arm keeps the percentage, where
nothing is broken (D57).

**Sharing D39's `budget` marker kind with the mount advisory,** or giving the
mount a marker kind of its own. Sharing makes the mount advisory eat the
edit-time one for the rest of the session — the session most likely to edit the
index next; a separate kind spends marker machinery on an emission already
one-shot, `add-tier.sh` reporting once per mount (D57).
