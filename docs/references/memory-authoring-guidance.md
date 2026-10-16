# Memory authoring guidance — decisions D47, D48

Where the guidance for writing a fact and curating the index lives and where it
is invoked: a skill that fires on the write, a command a human starts, and the
three moments that act on facts already written. One of the six nodes of the
tiered-memory subsystem (FR15), whose entry point is
[tiered-memory.md](tiered-memory.md). The hook pair that syncs the index with
frontmatter, the routing-key advisories (D39) and the drift sweep (D40) are in
[index-authoring-sync.md](index-authoring-sync.md).

- The authoring guidance — **D47** authoring guidance is a skill and curation is
  a command, shipped by the plugin rather than held as memories · **D48** the
  skill is invoked by directive at the three moments that act on facts already
  written

---

**D47 — Authoring guidance is a skill and curation is a command, shipped by the
plugin rather than held as memories**

The rules for what a fact says, whether it should exist, which tier it lands in
and whether its index line routes are `skills/memory-writing/SKILL.md`; the
store-wide pass — the two budgets and the loader cap, before-and-after
vocabulary counts, the two adversarial auditor briefs, the plain-word sweep and
the whole-submodule frontmatter review — is `commands/index-audit.md`. Both were
first written as memory facts in a shared tier and grew to 32 KB across two
files with the two longest index lines in the store, 1,459 B between them.

**A memory whose body reduces to "when writing a memory, do X" is owned by the
thing that fires at that moment.** That is the skill's own ownership rule
applied to itself, and gitlore is the plugin that owns the moment: it ships
`merge`, `push`, `recall` and `resolve`, and nothing owned authoring or
curation, which was a gap in the plugin's surface rather than a fact to keep.
The skill self-triggers on the write, so the moment is mechanical and
detectable; the audit is a pass a human decides to run, so it is a command. Off
the index, the seam between the two runs by moment rather than topic — the
trigger-writing half of the old curation fact fires on every memory write and
moved into the skill; budgets and levers fire only on a curation pass.

**Only a fact with a gitlore-owned moment converts.** Guide shape is not the
criterion. Facts that fire at "about to accept a green test" or "about to write
a design doc" stay memories, because gitlore owns neither moment.

**The descriptions are short.** A skill or command description is injected every
session exactly as an index line is, so carrying the line's routing surface into
the description would be a lateral move. Both triggers are computable — a write
under `memory/`, an explicit invocation — so neither description carries routing
surface; together they cost ~140 B of always-on context against the 1,459 B of
capped index they free. Evidence and provenance were cut rather than relocated:
the numbers that make a counterintuitive rule survive disagreement stay inline,
compressed to the figure, and the rest is in the changelog. The one reusable
artifact, the pair of auditor briefs, lives in the command as what it dispatches
with.

**No write-time hook, and no index-size trigger.** A `PreToolUse` deny on writes
under `memory/` would reach the pre-write moment at a turn's cost on every
session that writes memory, and the skill description already reaches it. An
index-size trigger fires on a condition that can be permanently true — the index
is O(N) against a fixed cap, binding near 139 facts at a disciplined 180 B per
line — so it is a livelock, and it would fire at session start before the task
has begun; D39's budget notice is the right altitude, a report a human acts on.
Whether constrained generation or unconstrained-then-review produces better
facts is left open; `just evals` can settle it. Precompact reads its directive
before it writes and handoff after, so the two placements are already split by
flow rather than held apart deliberately, and a comparison has to control for
that.

The skill ships no code, so D22's dependency argument does not reach it; D40's
drift sweep stays a manual reconcile distinct from this curation pass.

**D48 — The skill is invoked by directive at the three moments that act on facts
already written**

The skill's description reaches the moment a fact is *drafted* (D47). Three
other moments act on facts that already exist, with no write in flight for a
description to match: the **commit gate**, before the approval summary is
drafted; **`/gitlore:install`**, over a store just migrated from Claude Code's
own auto-memory; and a **tier mount**, over the local facts a newly active
tier's scope may now cover. At each of them gitlore already emits text the agent
reads, so the trigger is a sentence in that text — no new hook, and nothing
added to always-on context.

**At the gate the directive rides the shared approval clause**, so it reaches
all four D19 call sites, including the `handoff` consumer that discovers the
file through `gitlore.memoryApprovalClauseFile` and would otherwise commit
memory with no discipline applied — the drift D19 exists to prevent. The clause
is therefore two blocks: the review directive, then the message body spec. Its
placement is load-bearing rather than cosmetic: the review's edits must land
*before* the summary, because the summary states what the facts claim as
committed and an edit after it describes a commit that no longer matches. It
also keeps the summary's freshness check honest — `gitlore_commit_msg_freshness`
compares the message file's mtime against the newest memory file, so a fact
edited after approval invalidates the approval anyway.

**Install conditions the review on an announcement, not on the store existing.**
`init-submodule.sh` prints
`gitlore: migrated auto-memory from <src> into <path>` on the branch that copies
real facts in; the scaffold branch prints nothing, because a store gitlore
itself seeded has nothing to hold against the skill. Those facts were written
under CC's generic memory instructions — no review gate, no index cap — and this
is the one moment they are all in hand. The review's edits sit uncommitted on
top of the installer's `Initial memory` commit and reach the user through FR11
when memory is next committed, which is the intended path rather than a gap:
install is git-atomic for *wiring*, and a fact change is content.

**The mount's trigger goes in the nudge, not only in the command.** The
post-mount triage nudge fires on any manifest change, including a hand edit of
`.gitlore-tiers` that never ran `/gitlore:add-tier`, so the nudge is the
mechanical surface and the command body is the one a reader of the command
finds; both name the skill. What the judgement needs is the skill's tier test
and its rule about `[[links]]` that die when a fact leaves the repo, which the
nudge names rather than restates.

**Ordering at a gate is the skill's own business**, so §9 of `SKILL.md` carries
it: discard and relocate first — a fact leaving the store needs no body or index
work — then the survivors' bodies, then their index lines. An index over the
loader cap is explicitly not the gate's business; retirement across the store
stays `/gitlore:index-audit`, taken as its own decision.

What the bats suites can hold is that each site names the skill, that the
clause's directive precedes its body spec, and that the migration announcement
fires on the migrating branch and not the scaffold branch. Whether the agent
invokes the skill on being told to is agent behaviour, and belongs to the eval
tier (NFR9).

## Rejected alternatives

**A `PreToolUse` deny on writes under `memory/`** to inject the authoring rules
before the fact is drafted. A hook cannot force a tool call, and an
`additionalContext` payload past ~2 KB is spilled to a file with only the head
inlined, so the body could not ride it anyway; the skill description reaches the
same moment at no per-session turn (D47).

**An index-size trigger** that invokes the audit when the index crosses the cap.
The condition can be permanently true and fires before the task begins; the D39
notice is the right altitude (D47).

**Carrying the index lines' routing surface into the descriptions.** A
description is injected every session exactly as an index line is, so the move
would free the capped index only to spend the same bytes uncapped; both triggers
are computable, so neither description needs routing surface (D47).
