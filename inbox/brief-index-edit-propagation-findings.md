## Brief: three findings on index-edit propagation

2026-09-03

Found in `ddaanet/prohibitions` while reconciling 13 tier index lines with
their facts' `description:` frontmatter. Verified against gitlore 0.7.1 as
installed in `~/.claude/plugins/cache/ddaanet/gitlore/0.7.1`.

Three independent findings, ordered by how much they mislead an agent. Each is
observed behaviour, not a reading of the source.

### 1. Composition's own `additionalContext` denies what composition does

`index-compose.sh` ends its report with, verbatim:

> Composition moves or drops lines; it never changes a line's text.

It does change a line's text. Two root index lines were reworded, and
`gitlore_compose` rewrote exactly those two lines in
`memory/ddaanet/MEMORY.md` to match — text, not placement.

The behaviour is the useful one; the sentence is the defect. What it costs is
specific: an agent that believes it treats a stale carrier line as something
the tooling structurally cannot fix, and so either hand-edits the carrier or
leaves it stale and ships it. In this session it did both — a legitimate
composition was reverted as if it had been a hand edit, then had to be redone.

Suggested fix: state what composition actually guarantees. Something like
"Composition places, drops and re-texts carrier lines from the root index; it
never edits the root index itself" is both true and still tells the agent not
to re-verify.

### 2. The frontmatter setter invents `originSessionId` provenance

`index-sync-post.sh` overwrites a fact's `description:` from the root line.
The setter it uses also stamps `node_type`, `originSessionId` and `modified`
on the way through.

On `memory/ddaanet/markdown-formatter-choice.md`, whose metadata block was
only:

```yaml
metadata:
  type: reference
```

the write produced:

```yaml
metadata: 
  node_type: memory
  type: reference
  originSessionId: <the editing session>
  modified: <now>
```

The fact was authored 2026-08-25 by a different session. `originSessionId` now
names the session that touched its description weeks later, which is false
provenance in a field whose whole purpose is provenance — and it is unrecoverable
from the file afterwards. (`metadata:` also picks up a trailing space.)

Suggested fix: stamp `originSessionId` only when creating a file, never when
updating one. `modified` is fine to restamp — the file did change.

### 3. An index edit inside a subagent propagates to nothing

Both `PostToolBatch` passes key on the root index changing during their own
batch, via the pre-image `index-sync-pre.sh` stashes. A subagent's tool calls
batch in the subagent, so a root-index edit made there appears to reach
neither pass in the parent session.

Observed, and this is the sharp part — the staleness is silent and ships,
because the carrier is what the tier's remote receives.

Repro as it happened:

1. Parent session dispatches an `Agent` subagent to edit `memory/MEMORY.md`.
2. Subagent rewrites one tier line's text. Carrier goes dirty (composition
   evidently did run for this one).
3. Parent reverts the carrier from HEAD.
4. Subagent rewrites a second tier line's text in the same file.
5. Carrier stays clean. No recomposition, and the parent had to run
   `gitlore_compose` by hand to close the gap.

Step 2 versus step 5 is the part worth explaining before fixing: the same
operation propagated once and then did not. Cause not established — a
subagent's batches not running the parent's `PostToolBatch` hooks fits, so
does a stash consumed by the earlier batch, and the two want different fixes.

### Constraints

- Findings 1 and 3 are about the same surface and may share a fix; 2 is
  independent.
- Finding 1 is a message-only change if the behaviour is intended. Confirm
  which of the two is the contract before editing either.
- No changes were made to gitlore from the reporting session — this is a
  report, not a patch.

### Additional context

The reconciliation that surfaced these is recorded in
`ddaanet/prohibitions:plans/2026-09-03-index-description-sync.md`, including
the byte accounting and the two index lines whose wording changed. Nothing
there is needed to act on this brief.

Worth knowing while triaging: `memory-writing` §7 already states that the
index line is canonical and the `description:` is synced from it. The 13
descriptions reconciled in that session had *never* matched their lines in the
tier's 228-commit history — each pair was authored separately in the fact's
own creating commit. If the sync hook is meant to keep them in step, it has
only ever run on the lines an agent happened to edit afterwards.
