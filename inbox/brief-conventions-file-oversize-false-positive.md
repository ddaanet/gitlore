## Brief: memory-size hook false-positives on the `@`-imported conventions file

2026-09-16

Raised from an edify session that edited `memory/ddaanet/shared-claude.md` to
retire a stopgap convention. The write succeeded and the hook then instructed
the agent to destroy the file's content.

### The defect

The PostToolUse memory-size hook fires on any write under the memory store and
judges every file against the recall budget:

> Error: this write left the memory file at ddaanet/shared-claude.md at 17.3KB,
> over the 4KB recall limit. The write succeeded, but recall shows other
> sessions only the first 4KB of a memory file, so everything past that is
> invisible unless they open it. Rewrite it to under 2.8KB now: keep one fact
> per file, split distinct facts into their own files, and summarize logs
> instead of appending. Do not continue it as a `-2` file.

`shared-claude.md` is not a recall-fetched memory fact. It is the always-loaded
conventions tier: each mounting repo's `CLAUDE.md` contains
`@memory/ddaanet/shared-claude.md`, so it loads **whole**, every session, in
every repo mounting the tier. The 4KB figure is the recall display limit and
has no bearing on a file reached by `@`-import. The file states this in its own
header, and the header is past the 4KB mark.

Complying is destructive and irreversible in effect: cutting a ~17KB shared
conventions file to 2.8KB strips standing rules from every ddaanet repo. The
instruction is also unusually forceful — "Rewrite it to under 2.8KB now",
plus a pre-emptive block on the `-2` escape — which is exactly the shape an
agent complies with without checking. The edify session declined and reported
it, but that depended on the agent knowing why the file exists.

### Constraints

- The hook cannot distinguish the conventions tier from an ordinary fact by
  path alone: both live under the memory store, and the tier directory holds
  both `shared-claude.md` and genuine per-fact files beside it.
- Any fix must keep the real check working for the fact files in the same
  directory — this is a carve-out, not a relaxation of the budget.
- The file is expected to be large and to grow. Its actual budget is editorial
  (every line is paid for by every session in every mounting repo), which is
  not a byte count a hook can check.

### Suggested shape, not a decision

Exempt the conventions file by name. The tier's conventions file is a known,
fixed filename the tooling already understands — `add-tier` creates it and the
mount wires the `@`-import — so the hook can skip exactly that name rather
than inferring intent. A generalisation worth considering: skip any memory
file that some `CLAUDE.md` in the repo `@`-imports, since an imported file is
by definition not recall-fetched.

Verify before implementing. The quoted text above is from a live firing and is
accurate; the claim about which component owns the check is an inference from
the message, not something the edify session confirmed in gitlore's source.

### Additional context

- The edify session recorded the workaround as a tier memory fact,
  `ddaanet/shared-claude-oversize-false-positive.md`, so agents meeting the
  warning stop complying with it. **That fact is a workaround for this
  defect.** When the hook is fixed, retire it — it costs index bytes in every
  mounting repo, against an index already at ~104% of its loader budget.
- Unrelated and already reported elsewhere: that loader-budget overflow in
  `memory/MEMORY.md` is real and silently truncates the tail of the index.

### Boundary

edify's session made no changes in this repo beyond dropping this file. This
brief is the end of that involvement, not a ticket held open.
