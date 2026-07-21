# D17 slice 3-ii — tier index composition

*2026-07-21. Implements the composition paragraphs of design decision D17
(`docs/design.md`). Slice 3-i-a (tier materialization, propagation-in, routing
guidance) and the tier commit/push lockstep are already done; this slice makes a
tier's pointer lines appear in the always-loaded root index, and makes a
locally-authored tier line travel back to its carrier.*

## Problem

Only the root `MEMORY.md` is always-loaded, so a fact whose pointer lives in
`memory/ddaanet/MEMORY.md` is not reliably recall-reachable. The tier's *bodies*
already arrive (SessionStart fast-forward), and the tier already commits and
pushes in lockstep. What is missing is the index surface: the tier's lines must
be spliced into the root index, and a line authored in the root against a tier
file must be mirrored back into the carrier so it travels to other consumers.

## Model

**Line identity is the path prefix.** No sentinel text is injected into any
index. A root-index bullet whose path's first component names a **mounted** tier
(an entry in `memory/.gitmodules`) is that tier's line. A bullet with no `/` is a
project line.

**Two directions, one function.**

- *Splice up*: each active tier's carrier bullets appear in the root index with
  the mount dir prefixed — `- [T](foo.md)` in `memory/ddaanet/MEMORY.md` becomes
  `- [T](ddaanet/foo.md)` in `memory/MEMORY.md`, so the always-loaded Read
  resolves to `memory/ddaanet/foo.md`.
- *Mirror down*: each root bullet attributed to an active tier is written into
  that tier's carrier with the prefix stripped.

**Composed layout.** `[preamble] [tier blocks, manifest order] [project bullets]
[trailer]`. Each tier block preserves its carrier's line order; project bullets
keep the order CC arranged them in. No headers, no blank lines, no separators
between blocks — the region between the first and last bullet is pure bullets, so
the pass is byte-idempotent and injects no text CC could mistake for content.

**Preamble / trailer** are everything before the first pointer bullet and after
the last. They are copied verbatim. The same layout rule governs the carrier when
mirroring down. An index with **no** bullets is all preamble, and mirrored-down
lines are appended after it — which is the day-one state of `memory/ddaanet`,
whose carrier is frontmatter and prose only. So the first compose splices nothing
up and mirrors the existing `ddaanet/`-prefixed root lines, if any, down.

## Composition is placement only

It never derives, edits, or reorders a line's *text*; never touches project
bullets; never creates or deletes a memory *file*. It owns exactly one thing: where
a tier's bullets sit in the root index, and whether the carrier has them.

Consequence for the existing index→frontmatter sync: composition preserves the
`(path, hook)` set of the root index, and `index-sync-post.sh` keys per line on
what changed, treating a reorder as a no-op. A spliced-up line is *new* to the
root index, so the sync sees an added line and applies fill-if-empty against the
tier file — which already carries an authored `description:` from its home repo,
so nothing is clobbered. The two hooks do not interact, in either firing order.

`index-sync-post.sh:59` already resolves an index path as `$mempath/$path`, so a
prefixed path resolves to the tier file with **no change to the sync**.

**Mirror-down is unconditional** — no check that the carrier file exists. A
missing file would only matter under a rule about whether the file set or the
index is authoritative over a line's *presence*, which D17 deliberately leaves
open pending evidence. Composition stays structural and does not decide it by
the back door.

## Validation — fail-safe, identical everywhere

The pass refuses as a whole, leaves every index untouched, and reports on
`systemMessage` (user) + `additionalContext` (agent), when:

1. the composed result would carry a **duplicate** pointer path;
2. the manifest **lists a tier that is not mounted** (stale or mistyped entry);
3. a root bullet's path has a `/` whose first component names **no mounted
   tier** — an unattributable prefix. Unlike a mounted-but-inactive tier (whose
   block is dropped because the lines survive in its carrier), this line has no
   carrier to survive in, so dropping it would be data loss. It is a leftover
   from a removed tier and needs a human;
4. a non-blank **non-bullet line sits between** the first and last bullet of an
   index it would rewrite — the layout rule would relocate it and lose its
   position.

A mounted tier *absent* from the manifest is not an error, only dormant: listed
-but-absent is broken, present-but-unlisted is fine.

## Triggers

- **`SessionStart`**, after the tier fast-forward, so propagated lines surface.
- **`PostToolBatch`**, when the batch wrote the root `MEMORY.md` or
  `memory/.gitlore-tiers` — one invocation per turn, all edits in the batch, one
  message. This is what lets the agent edit the manifest, see the regenerated
  index, and reorder within a session (the add-tier validate-and-reorder loop),
  and what carries a freshly-authored tier line down to the carrier before the
  FR11 commit rather than a session later.

No compose runs inside the FR11 pre-commit path: anything the agent authored is
already composed at end of turn. The one gap is an index merged by
`/gitlore:resolve`, which composes on the next batch or the next session —
recorded as a follow-up, not handled here.

## Routing guidance change

`session-start.sh` currently tells the agent to add the index line to the tier's
own `MEMORY.md` — a file the agent does not have loaded. With mirror-down in
place it becomes: write the file into `memory/<tier>/`, add its line to the
**root** index as `- [T](<tier>/foo.md) — hook`. That is the surface the agent
already has open, and composition carries it to the carrier.

## Components

- **`scripts/lib/index-compose.sh`** — pure functions, no side effects beyond the
  index writes: split an index into preamble / bullets / trailer; attribute a
  bullet path to a mounted tier or to the project; add and strip a prefix; build
  the composed root text; build a carrier's text; run the four validations.
  Mirrors `index-sync.sh` in shape and is unit-testable directly.
- **`scripts/cc-hooks/index-compose.sh`** — the `PostToolBatch` hook: decide from
  `.tool_calls[]` whether this batch touched the root index or the manifest, call
  the library, emit one message on both channels.
- **`session-start.sh`** — call the same library after the tier ff block; update
  the routing-guidance text.

Nothing may `exit 2` (a `PostToolBatch` cannot block a tool that already ran) and
stdout JSON parses only on `exit 0`, so a failure reports on `systemMessage` and
exits 0 — the D14 rule the sync hooks already follow.

## Testing

`tests/index_compose.bats` unit-tests the library against fixture stores: splice
up, mirror down, byte-idempotence on an already-canonical index, manifest
ordering with two tiers, a dormant mounted tier (block dropped, carrier keeps its
lines), preamble/trailer preserved, and each of the four validations refusing
with every index unchanged. `tests/cc_hook_index_compose.bats` covers the hook:
untouched batch → no-op, index-touched batch → composed and reported,
manifest-touched batch → recomposed, validation failure → both channels, exit 0.
Both go in `make test`.
