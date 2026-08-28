# Index authoring and sync — decisions D38–D40, D47

The authoring surface: what an agent edits when it writes a memory, how the
index line and the file's frontmatter are kept in step, and where the guidance
for writing a fact and curating the index lives. One of the four nodes of the
tiered-memory subsystem (FR15), whose entry point is
[tiered-memory.md](tiered-memory.md).

- The authoring surface — **D38** authoring-time sync is one-way, index →
  frontmatter · **D39** the two routing-key advisories · **D40** pre-existing
  drift is a manual sweep · **D47** authoring guidance is a skill and
  curation is a command, shipped by the plugin rather than held as memories

---

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
supply it either (Rejected alternatives, below).

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

**D47 — Authoring guidance is a skill and curation is a command, shipped by
the plugin rather than held as memories**

The rules for what a fact says, whether it should exist, which tier it lands
in and whether its index line routes are `skills/memory-writing/SKILL.md`; the
store-wide pass — the two budgets and the loader cap, before-and-after
vocabulary counts, the two adversarial auditor briefs, the plain-word sweep and
the whole-submodule frontmatter review — is `commands/index-audit.md`. Both
were first written as memory facts in a shared tier and grew to 32 KB across
two files with the two longest index lines in the store, 1,459 B between them.

**A memory whose body reduces to "when writing a memory, do X" is owned by the
thing that fires at that moment.** That is the skill's own ownership rule
applied to itself, and gitlore is the plugin that owns the moment: it ships
`merge`, `push`, `recall` and `resolve`, and nothing owned authoring or
curation, which was a gap in the plugin's surface rather than a fact to keep.
The skill self-triggers on the write, so the moment is mechanical and
detectable; the audit is a pass a human decides to run, so it is a command.
Off the index, the seam between the two runs by moment rather than topic —
the trigger-writing half of the old curation fact fires on every memory write
and moved into the skill; budgets and levers fire only on a curation pass.

**Only a fact with a gitlore-owned moment converts.** Guide shape is not the
criterion. Facts that fire at "about to accept a green test" or "about to
write a design doc" stay memories, because gitlore owns neither moment.

**The descriptions are short.** A skill or command description is injected
every session exactly as an index line is, so carrying the line's routing
surface into the description would be a lateral move. Both triggers are
computable — a write under `memory/`, an explicit invocation — so neither
description carries routing surface; together they cost ~140 B of always-on
context against the 1,459 B of capped index they free. Evidence and provenance
were cut rather than relocated: the numbers that make a counterintuitive rule
survive disagreement stay inline, compressed to the figure, and the rest is in
the changelog. The one reusable artifact, the pair of auditor briefs, lives in
the command as what it dispatches with.

**No write-time hook, and no index-size trigger.** A `PreToolUse` deny on
writes under `memory/` would reach the pre-write moment at a turn's cost on
every session that writes memory, and the skill description already reaches
it. An index-size trigger fires on a condition that can be permanently true —
the index is O(N) against a fixed cap, binding near 139 facts at a disciplined
180 B per line — so it is a livelock, and it would fire at session start before
the task has begun; D39's budget notice is the right altitude, a report a human
acts on. Whether constrained generation or unconstrained-then-review produces
better facts is left open; `just evals` can settle it. Precompact reads its
directive before it writes and handoff after, so the two placements are
already split by flow rather than held apart deliberately, and a comparison has
to control for that.

The skill ships no code, so D22's dependency argument does not reach it; D40's
drift sweep stays a manual reconcile distinct from this curation pass.

## Rejected alternatives

**Frontmatter `description` as the source of truth for the index one-liner.**
The two surfaces drift bidirectionally — the agent revises whichever one it has
loaded, and the other rots, in both directions. Deriving the index from
frontmatter would overwrite curated one-liners with stale text and degrade the
*reliable* retrieval lever. The index line is canonical; frontmatter drift is
healed by the one-way authoring-time sync (D26, D38).

**Scoring an index hook against its body, tf-idf style,** to flag a line with no
routing value. Refuted on the real store: over 76 documents `df ≤ 3` marks
ordinary prose words as distinctive, so the score tracks hook *length* rather
than quality (means 2.06 `reference` vs 1.76 `feedback` — no separation).
Document frequency needs a corpus a memory store will never have. The two
countable advisories — byte budget and missing trigger token — cover what is
checkable (D39).

**A `PreToolUse` deny on writes under `memory/`** to inject the authoring
rules before the fact is drafted. A hook cannot force a tool call, and an
`additionalContext` payload past ~2 KB is spilled to a file with only the head
inlined, so the body could not ride it anyway; the skill description reaches
the same moment at no per-session turn (D47).

**An index-size trigger** that invokes the audit when the index crosses the
cap. The condition can be permanently true and fires before the task begins;
the D39 notice is the right altitude (D47).

**Carrying the index lines' routing surface into the descriptions.** A
description is injected every session exactly as an index line is, so the
move would free the capped index only to spend the same bytes uncapped; both
triggers are computable, so neither description needs routing surface (D47).
