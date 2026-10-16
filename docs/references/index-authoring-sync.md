# Index authoring sync — decisions D38–D40

The authoring-time machinery: how the index line and the file's frontmatter are
kept in step by a hook pair, what that pass reports about a thin routing key,
how pre-existing drift is healed, and the relay that carries a subagent's report
to the side that can show it. Where the guidance for writing a fact and curating
the index lives and is invoked is in
[memory-authoring-guidance.md](memory-authoring-guidance.md). One of the six
nodes of the tiered-memory subsystem (FR15), whose entry point is
[tiered-memory.md](tiered-memory.md).

- The authoring-time sync — **D38** authoring-time sync is one-way, index →
  frontmatter · **D39** the two routing-key advisories · **D40** pre-existing
  drift is a manual sweep · **the relay**, D51's mechanism: a subagent's
  confined report is a write-once file keyed by session and agent, drained by a
  hook of its own

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
is per (agent, batch). The stash name carries the payload's `agent_id`, which
hook stdin sets only inside a subagent, so the main thread keeps the unsuffixed
name and a batch resolves only what its own agent stashed. It does not read
`.tool_calls[]`: the stash the pre half left is the whole signal, its presence
saying a watched call ran this batch and `cmp` against the file on disk saying
whether that call moved anything, which is also what covers a `Bash` call
announcing no path. The first watched call of a batch stashes and later ones
must not re-stash (that would diff against a mid-batch state and lose the
earlier edits' changes); the post-hook drops the stash at every batch end, even
one where the index went untouched, so a pre-image never outlives the batch that
took it. The key is what keeps one that does outlive it from becoming
*another agent's* baseline — a parent batch ending mid-subagent consumes and
removes its own only, and leaves the subagent's edit standing. A stash stranded
by an interrupted batch is consumed by that same agent's next batch rather than
discarded: the difference between it and the file is a propagation still owed.
One left by a subagent that died mid-batch is consumed by nothing, and since an
agent id is not reused the residual is one file per dead subagent rather than
unbounded growth — a bound stated in a comment rather than swept. The compose
hook's pre-batch stamp is its own file, keyed and dropped the same way, so
neither hook depends on running before the other. `PreToolBatch` would pair more
neatly but is unverified — absent from the hooks reference, with nothing
observed confirming it fires for a single call.

A frontmatter-only edit is left untouched; this hook never writes the index, and
it deploys globally through the plugin hooks. It is
**complementary to, not a substitute for, the structural recompose**: the sync
sees only in-session tool edits, so propagation arriving via a `/gitlore:merge`
take, merges or `/gitlore:resolve` is invisible to it — precisely what the
structural pass covers.

**Both hooks are non-blocking but never silent**. Neither may ever `exit 2`. For
`index-sync-pre.sh` the reason is its event: `PreToolUse`, where exit 2 blocks
the write. At `PostToolBatch` exit 2 ends the turn with an empty reply and shows
the agent its stderr only on the next user turn, and exit 1 or 3 goes on with
the agent seeing nothing (the measured table is in D60,
[cc-platform.md](cc-platform.md)). But `exit 0` is not licence to swallow
errors: a genuine failure (the stash `cp` fails; a frontmatter write fails)
reports on `systemMessage`, the D14 channel. Here `exit 0` is
*required for visibility rather than merely tolerated*, because
**stdout JSON is parsed only on exit 0** — a non-zero exit discards the
`systemMessage` and reaches the user as a bare notice and the agent not at all.
The post-hook checks each `gitlore_set_frontmatter_description` explicitly (an
`if !` condition, which suspends `errexit`) so one bad target cannot abort the
loop and strand the rest. A death the checks do not anticipate — `awk`, `cmp`
and `grep` exit 2 on a file they cannot open — meets the guard every
`PostToolBatch` hook calls once its memory path resolves
(`gitlore_batch_hook_guard`, D60): it captures the hook's stderr and, on a
non-zero exit, emits one object with the hook name, the status, the failing
command with its line and the captured error on `systemMessage`, the same plus
the hook's consequence sentence on `additionalContext`, and exits 0. Only a
guard that cannot capture or encode replays the stderr and exits with the
original status, 2 turned into 1.

The post-hook claims its baseline by renaming the stash to `<name>.$$` before
reading it, so `index-sync-pre.sh` and a second copy of the hook see no baseline
while one works on it. A claim that finds the stash already gone was won by
another copy and exits 0 quietly; a stash still in place that will not move is a
death the guard reports. The claimed copy is consumed on every exit, the guard's
trap removing it after a death too: a surviving pre-image is a hazard, since a
later silently-failed `cp` would leave the next post-hook diffing a fresh index
against an ancient baseline and propagating wrong hooks. `|| true` and a bare
`|| exit 0` on a fallible command are rejected as dishonest error paths.

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

**The relay — D51's mechanism**

Inside a subagent both channels reach that subagent's own transcript and nothing
else (D51, measured under CC 2.1.261), so a keyed run also writes its two bodies
to a report file in the memory gitdir. That staging is
**in addition to the subagent's own emission, not instead of it**: the subagent
is the actor and gets its copy, and a write that fails says so on the subagent's
own `additionalContext`, where the actor is asked to repeat the report in its
reply. A report therefore names the agent that wrote it, as the pre-image's key
does, without sharing the pre-image's consumer — a baseline is consumed by the
agent that took it, a report by the side that can show it.

**A report is a write-once file, never merged.** Its name is
`gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>`: the sanitized session id (`nosession`
when the payload carries none), the sanitized agent id, `date +%s`, the writing
process's pid, and the writer's tag, `sync` or `compose`. Every hook matching
one event runs in parallel ("All matching hooks run in parallel",
code.claude.com/docs/en/hooks), so a read-merge-write on one shared marker drops
whichever report loses the race; two hooks in one batch write two files and have
nothing shared to race on. The file is built at `<name>.tmp` and installed by
`mv` inside the gitdir — a same-filesystem rename — and a name already occupied
is refused with the temp removed rather than overwritten, since POSIX `mv` moves
a source *into* an existing directory. Residual: two writes agreeing on session,
agent, tag and wall-clock second **from one process** collide, and the second is
refused through that caller's "could not be staged" line. No caller does that —
the two reporting hooks are separate processes carrying different tags.

**One `PostToolBatch` drainer.** `scripts/cc-hooks/relay-drain.sh` is the only
`PostToolBatch` hook that reads a report; `SessionStart` drains too (below). It
is a `PostToolBatch` hook of its own rather than a branch inside the two
reporting hooks, for two reasons that follow from the same parallelism: a drain
living in both would run twice on a batch that fires both, framing and emitting
every report a second time; and each of those hooks runs only when its own
baseline fired, so a drain living in either would skip the batch whose `Agent`
call returned — the batch that changed no index, left no stash and no stamp, and
is exactly the one the subagent's report was staged for. The drainer takes no
baseline of its own: it runs on every batch of the main thread, and the files
alone decide whether it says anything. A keyed run exits at once, because a
subagent only ever writes toward the next parent-side run.

**It drains its own session only.** A subagent's hook payload carries the
*parent's* `session_id` (the same measurement, CC 2.1.261), so the name says
which conversation a report is owed to, and a peer session in the same checkout
cannot take it. The drain enumerates `gitlore-relay-<S>-*`, frames each file
`--- gitlore-relay agent <A> ---` on both channels in `LC_ALL=C` filename order
— grouped by agent, then by write time — and removes exactly the files it read.
Unique names are what make that safe: a drain never removes a file it did not
read, so nothing has to be claimed before it is read. `.tmp` is excluded from
every drain, so a temp whose writer was killed before installing it is never
folded in as a report of its own; the residual is that it is never folded at
all, and only the age sweep collects it.

**`SessionStart` drains the same session, then sweeps by age.** `compact` and
`resume` keep the session id and fire no `PostToolBatch` of their own, so this
pass delivers at the compaction or resume itself instead of leaving a waiting
report to the session's next batch — and it is the whole delivery for a session
that runs none. The sweep then removes every relay file older than seven days
regardless of session, temps included — the `.tmp` exclusion is a drain rule,
never a sweep rule. A report addressed to a session that ended is undeliverable:
the conversation it describes is gone, and the store state it reported on is
re-covered by `SessionStart`'s own structural pass. It goes by age rather than
into a stranger's session.

**Two residuals bound delivery.** Between the drain and the emit the reports
exist only in the hook's variables and the files are already gone, so a hook
killed in that window loses them; the drainer parses its payload first, which
establishes that `jq` works at all and narrows the window without closing it
(claim-by-rename would close it, and is rejected in
[cc-platform.md](cc-platform.md)). And a background subagent whose report lands
after the parent's last batch of a turn waits for the parent's next batch, or
for the next compact or resume; a session that ends with no further batch loses
it to the sweep.

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
pass names the percentage. It is arithmetic, so it has no false positives.

Both channels word it as **ambient information, not a goal**: the number says
nothing about whether any particular fact should go, and an agent that reads it
mid-write as an instruction to get under the line abandons the write it was
asked for to curate a store nobody asked it to curate. Deciding what goes is the
store-wide pass's business (`commands/index-audit.md`, D47, in
[memory-authoring-guidance.md](memory-authoring-guidance.md)), which a human
starts.

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
