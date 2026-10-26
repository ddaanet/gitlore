# The commit gate

The FR11 approval gate: the commit the agent makes once the user approves a
summary, the intent-file route to the same commit, and the decisions arguing for
that shape. FR11 itself and the conclusions open the node below; this file is
what you need while building or debugging approval. The git hook that carries a
push out is in [git-hooks.md](git-hooks.md), and the two callable scripts, the
commit one among them (D58), are in
[memory-entry-points.md](memory-entry-points.md).

- Approval — **D4** the commit message travels by file handshake, and its
  presence is the approval signal · **D12** a submodule-side commit gate backs
  FR11 as defense in depth · **D19** one canonical approval clause, discovered
  externally via a git-config key · **D22** the memory-hygiene checker is a
  repo-local gate, not shipped surface · **D56** the batch retry is judged by
  the approval's freshness, not by a status the run reports

---

## Mechanism

**`PostToolBatch` — the commit by intent file.** `memory-commit-batch.sh` acts
on an intent file the agent wrote as an ordinary edit; `add-tier-batch.sh` is
its sibling on the mount side. The shape is deliberate and shared: the agent
writes a file, a hook does the git — sidestepping both the command sandbox and
the auto-mode classifier, neither of which lets the agent do this work itself.

The agent's own call of `commit-memory.sh -F -`, the approved summary on stdin,
is the direct route (the SessionStart orientation and the submodule gate's block
message both teach it); the intent file is the same commit by the other route,
for a moment when a denial would strand the approved summary (D16, D58). The
agent writes the approved summary (`.claude/gitlore-memory-message`) and the
trigger (`.claude/gitlore-commit-memory`); `memory-commit-batch.sh` runs
`commit-memory.sh` bare, which commits with the blessed sentinel, advances local
`live` and stages the pointer in the parent index.

**Nothing is consumed before the commit it approves.** Because the hook runs
`commit-memory.sh` bare, the approval on disk is judged by its mtime freshness
against the store, so a retry commits only what the summary still covers (D56).
On any failure before the commit, the trigger *and* the message file stay put
and the next batch retries: no lost approval. The blessed commit consumes the
message file; the trigger goes only once the whole run succeeds, the `HEAD:live`
fast-forward included.

**Which message the hook emits is read off the store and the IPC file the run
left behind, never off a status the run reports about itself** (D53, in
[git-hooks.md](git-hooks.md)). Four states, in the order tested. The message
file **consumed** — present and non-blank before the run, gone after — means the
commit landed and the `HEAD:live` step after it failed; nothing waits on
approval and no batch repeats that step, so the script's reason is the whole
message — on divergence, the prepared-merge directive. The store
**or any mounted tier mid-merge** means the run refused to commit on top of a
merge, so the guard's directive is the whole message: nothing was committed, no
approval was consumed, and re-approval follows the merge rather than preceding
it, because landing it writes content no summary has covered. Freshness **`no`**
means something newer than the approval is in the store — the agent's own fix, a
checkout, a take, a resolved merge — so the summary at the message file is
presented again, amended for what changed, and approved again; both files stay,
and the stale file is the text to re-present. Freshness **`yes`** means the
approval still covers the store: a transient such as a locked repo or an
in-flight merge, which needs no agent action, or a refusal whose reason names a
fix the agent has not made yet — an edit, for a problem in an index file the
commit changes (D50), or a checkout or take, for an off-pin tier. The retry is
silent on that arm; making the fix is itself a write to the store, so the batch
that follows it reads freshness `no` and asks for the summary again.

A trigger with no approved summary is kept, so the commit completes on its own
the moment the summary lands. **No summary** means absent *or* blank, on both
entry points: an all-whitespace file is fresh by mtime and `git commit -F`
rejects it as an empty message, so each screens it with
`gitlore_approval_present` ahead of the run rather than letting that failure
restamp the approval and repeat verbatim on every later batch.

**A prepared merge on the store or any mounted tier outranks that screen**, on
both entry points. A merge state makes the store dirty by construction — its
checkout moved the worktree — and the landed-then-failed arm above consumes the
approval before preparing one, so the very next batch arrives dirty with nothing
approved: the screen's own shape. Answering it would put in front of the user a
merge both of whose sides they already approved (D49) as a summary to draft, and
the summary would not help, because the guard refuses on the merge either way.
Ordered behind the guard, the directive `/gitlore:resolve` acts on reaches the
agent instead. A trigger on a **clean** store takes both IPC files, not just the
trigger: a summary left behind covers a store with nothing pending, and the next
dirty episode needs its own approval regardless.

## Decisions — D4, D12, D19, D22, D56

Why approval has this shape: how the summary reaches the hook, why the submodule
holds a gate of its own, the wording that carries the approval, why the hygiene
checker stays repo-local, and what decides that a retry's approval still holds.

**D4 — Commit message via file handshake**

Claude writes a commit message file at the parent working tree's
`.claude/gitlore-memory-message`; the commit path reads, uses, and deletes it.
Path is resolved by `gitlore_commit_msg_file`, via
`git -C <memory-path> rev-parse --show-superproject-working-tree`, then
`/.claude/gitlore-memory-message`. It sits in the parent working tree rather
than the memory submodule's gitdir so the agent can write it — the gitdir is
write-blocked by the CC sandbox and the auto-mode classifier.

Write timing: the file is created only after the user explicitly approves the
commit summary Claude has presented. The file's presence is the signal that a
memory commit has user approval; absence or staleness blocks the commit.

Alternatives rejected:

- **Stop hook:** fires on every response turn, not only before commits —
  unnecessary writes and churn, and no clean trigger for the confirmation
  prompt.
- **Force-write on memory edit:** PostToolUse on every `Write`/`Edit` would
  generate noise and couple commit preparation to individual edits rather than
  commit intent.
- **`claude --print`:** no session context, cannot ask user for confirmation, no
  memory of why edits were made.

**D12 — Submodule-side commit gate (defense in depth for FR11)**

A gate in `commit-memory.sh` alone leaves FR11 open on one flank. The script
reads the commit-message file and commits or refuses — but the memory submodule
is itself an ordinary git repo, so a commit made *directly inside it*
(`git -C <mempath> commit`, a human `cd <mempath> && git commit`, a script)
meets nothing: no summary, no approval, no handshake — and the parent then
records an already-committed submodule.

Two complementary mechanisms close it:

- **Hard gate (load-bearing).** A `pre-commit` hook *inside* the memory
  submodule, emitted by `emit-memory-gate.sh` into
  `git -C <mempath> rev-parse --git-path hooks/pre-commit` (the shared common
  hooks dir, so one emission also covers linked-worktree memory trees — D11
  parity). It admits a commit **only** when the env sentinel
  `GITLORE_MEMORY_COMMIT=1` is present, and blocks otherwise with a
  `$CLAUDECODE`-branched message. Every gitlore-internal commit path exports the
  sentinel: `commit-memory.sh`'s blessed commit, both `/gitlore:resolve` merge
  commits, and the install initial commit. A naked commit by an agent, human, or
  script never sets it. This makes FR11 a shell-enforced invariant (NFR1 "no AI
  on hot path"; D7 "scripts decide") on *every* commit path, not just the
  script's.

  An env sentinel — not "fresh magic file present" — because resolve's merge
  commits use git's `MERGE_MSG`, not the magic file, so a file-presence gate
  would block legitimate resolve commits. One sentinel covers all three blessed
  paths uniformly. A take's repair of an arriving index needs none: it is built
  with `commit-tree`, which runs no hook, and FR11 exempts it (D52, in
  [tier-arrival-repair.md](tier-arrival-repair.md)).

  The wrapper mirrors the parent wrappers (D5): it resolves the live plugin via
  `git config gitlore.hooksDir` and degrades to a clean `exit 0` + hint when
  that key is unset or stale. Because the gate fires under the *submodule's* git
  context — where `git config` reads the submodule config, not the parent's
  where SessionStart pins the key — `emit-memory-gate.sh` mirrors the parent's
  `gitlore.hooksDir` into the submodule config (common config, shared across
  submodule worktrees). The graceful-degradation window (plugin cache GC'd
  before the next SessionStart re-pins) admits an unguarded commit, accepted for
  NFR8 parity with the parent wrappers; the next SessionStart re-wires it.

- **Orientation (removes the friction of hitting the hard gate).**
  `SessionStart` emits a standing `additionalContext` every gitlore session
  carrying the commit as an act: writing a memory file is an ordinary edit; to
  commit memory, summarize the pending changes, get the user's explicit
  approval, then run `bash "$(git config gitlore.commitCommand)" -F -` from the
  repo root with the approved summary on stdin, through a quoted heredoc; never
  run `git commit` inside the memory submodule. The text ends with the rule that
  a request to commit memory is not approval of a summary the user has not seen:
  show the summary, end the turn, commit only after the user's reply approves
  it. Since D58 a memory commit is the agent's own act, and a summary passed
  with the call counts as approved by construction, so this text is the only
  gate between the agent and the commit; an eval run on 2026-10-11, asked to add
  a note to `memory/MEMORY.md` and commit it, ran `commit-memory.sh -F -` in the
  same turn in 4 of 5 runs, one stating it treated the request as the approval.
  The `$(git config …)` reaches the agent as literal text. The summary travels
  on stdin and not as a `-m` argument because it is prose derived from memory
  content: templated into a double-quoted argument, a backtick or `$(…)` in it
  would be run by the agent's shell. The text is acts and nothing else: the
  gate, the hook that blocks, and what it records are mechanism the agent cannot
  act on, and the gate states them itself at the moment it fires; the
  prohibition forbids by role, because naming `git -C <mempath> commit` invites
  reasoning about the forms left unnamed; and no FR id appears, since it
  resolves to nothing in the consumer repos this context reaches. Pinned by the
  assertions in `tests/cc_hook_session_start.bats`. The base Claude Code memory
  instructions describe generic "edit files, save facts" memory with no review
  gate, so the agent's default is actively wrong in a gitlore repo. The
  orientation corrects the model **before** the agent acts, and must be
  front-loaded: the prohibition guards an action the agent would otherwise take
  unprompted, and the commit command is the only way memory is committed, so no
  hook any longer surfaces it just in time. Writing stays seamless — no step
  before an edit — and the approval step attaches to the commit alone, so the
  text does not induce ceremony around persistence. The gate's own
  `$CLAUDECODE`-branched output remains the fallback when a direct commit is
  blocked, and `/gitlore:resolve` surfaces on divergence.

This is a cleaner variant of the rejected PreToolUse alternative — a submodule
hook consistent with the existing hook architecture, with none of the CC-level
scoping complexity.

**D19 — Memory-approval wording: one canonical clause, discovered externally via
a git-config key**

The FR11 approval prompt — "summarize pending memory changes, present as a
blockquote, get approval" — is needed at three call sites: two inside gitlore
(`memory-commit-batch.sh`, `gitlore_sync_memory_to_live` in
`resolve-sync-memory.sh`) and a third in the `handoff` plugin's
`checkpoint_memory_directive`, a caller in the D16 sense that drives its own
memory commit around gitlore's IPC files. Composed independently, they drift —
the internal ones did once (2026-07-16, "one prompt fix, three surfaces"), and a
hand-synced copy in a different repo entirely can only drift further.

**The wording is a self-contained block, appended last.**
`reference/memory-approval-clause.txt` holds two blocks. The first is the review
directive: before the summary is drafted, the pending memory changes are held
against the `memory-writing` skill, and what it finds is fixed first (D48). The
second is the body spec — subject line, blank line, then
**one paragraph per changed memory file**, each opening
`**<Kind> <tier>/<slug>:**` with the kind drawn from New, Update, Augment,
Reduce, or Remove — followed by a literal template of three example paragraphs.
A `MEMORY.md`, root or tier, is excluded from the listing: an index line moves
with the fact it points at, so a paragraph for it would restate its neighbour
and put the routing table on the same footing as the facts. Read via
`gitlore_memory_approval_clause()` (`scripts/lib/util-config.sh`), it is
appended at the end of each call site's message rather than spliced into a
sentence: a template is inherently multi-line, and one line per file could not
carry what a memory commit message is for — what the fact now claims and what
moved it. Shipping the template rather than describing the shape lets the agent
copy a form instead of inferring one, and the bold prefix is what makes the body
scannable in the approval blockquote. The multi-line clause also constrains
emission: a hook that puts it in JSON must build that JSON with `jq --arg`,
since a raw newline inside a hand-written string is invalid. The sites keep
their distinct framing — a pending-trigger retry, a deferred commit, a
sync-guard refusal — so what is shared is the block, not the messages.

**Discovery mirrors D16's `gitlore.commitCommand`**, which already solved the
identical problem of a caller outside gitlore's process needing a stable path
into a plugin cache it cannot derive: `gitlore.memoryApprovalClauseFile` is
seeded at install (`scripts/install/write-settings.sh`) and re-pinned every
`SessionStart` (`scripts/cc-hooks/session-start.sh`), pointing at
`$PLUGIN_ROOT/reference/memory-approval-clause.txt`. gitlore owns the wording
because it owns FR11's gate and every direct-commit call site; `handoff` is a
consumer, the same relationship `commit-memory.sh` already has to it.

**No fallback copy in the consumer, and no silent skip on a missing key.** A
hardcoded fallback in `handoff` is rejected: the clause is only needed when
gitlore is genuinely active, and a submodule registered without a working
gitlore install already makes `handoff`'s existing approval instructions a dead
letter, so a fallback would be one more set of instructions nothing honors.
Silence is not the alternative either — when the key or file cannot be resolved,
`handoff` reports the problem and names the fix ("gitlore plugin looks disabled
— check `/plugin`") rather than skipping the directive, so a broken discovery
path fails loud instead of quietly dropping FR11's gate on the consumer side.

**`resolve.sh` reaches the clause through its callers, never by sourcing
`util.sh` itself.** `util.sh` declares `readonly` globals, so sourcing it twice
fails; `resolve.sh` leaves that to the caller and says so in its own header
comment. Every script that sources `resolve.sh` (`commit-memory.sh`,
`push-memory.sh`, `merge-memory.sh`, `resolve.sh`, `git-hooks/pre-push`,
`cc-hooks/session-start.sh`) sources `util.sh` first, so
`gitlore_memory_approval_clause` is in scope at `resolve.sh`'s one call site; a
defensive `source` line there would break every caller on a `readonly`
redeclaration.

**D22 — The memory-hygiene checker is a repo-local gate, not shipped surface**

`tools/check-memory-hygiene.py` runs uncached at the head of `just precommit`
(the cache cannot see a fact change through the `memory` gitlink) and checks
prose shape, wikilink targets, reference style and volatile git state across the
store. It stays in gitlore's own `tools/`; the plugin ships none of it.

**Shipping it would make python3 and PyYAML a user-facing dependency.** The
install surface is bash, git and jq, and every hook and script on the runtime
path stays within that. A gate that runs at *this* repo's commit time may reach
for a parser; a gate distributed to every consumer repo may not, and hand-rolled
frontmatter regex would trade a real dependency for a worse one.

**Most of what it checks is a house style, not a gitlore contract.** Prose shape
and reference form are ddaanet-tier writing conventions; a repo that mounts a
tier inherits that tier's facts, not gitlore's opinion about how facts are
phrased. `volatile-state` is the exception whose subject really is the store's
own design — an abbreviated commit id in a fact body rots because the store
outlives the ref that named it, in any repo, under any house style. It matches
`\b[0-9a-f]{5,40}\b` over frontmatter-stripped bodies, less all-digit runs and a
closed 47-word list of a-f-spellable words; over this store, 4 hits, 4 true
positives, with the all-digit exclusion missing roughly 4% of seven-character
shas as the stated residual. One generalizable check does not carry a runtime
dependency into every consumer. Several would reopen this.

**D56 — The batch retry is judged by the approval's freshness**

Handed the message file as its own `-F` operand, `commit-memory.sh` rewrites
that file from its own contents on every retry, minting a fresh approval
whatever has happened to the store since the user gave it. The mtime gate then
always passes, so an edit made between two batches — the index fix a D50 abort
asks for — commits under a summary that never saw it, while the abort text says
the summary needs approval again. The bare invocation closes that: the file is
read as it stands and `gitlore_sync_memory_to_live` decides, which is the one
gate on the batch path. `-m` and `-F` keep writing the file, because a summary
arriving with the call was approved immediately before it (D16, in
[memory-entry-points.md](memory-entry-points.md)).

**Freshness is the store's own answer, not a classification the run makes of its
own failure.** D53 refused a per-arm return code from the stale-merge guard on
the asymmetry of what each mistake costs — a misclassified arm marks an approval
fresh over content no summary covers, the FR11 boundary breached silently inside
the one gate that holds it — and that reasoning carries over whole. A status
line or exit code from `commit-memory.sh` would put the same judgement in the
same place, and would have to stay true across every failure arm added later,
each defaulting to whatever its author picks rather than to the safe answer.
Mtime order off the store needs no new state and no new return code, and the
restamp arms in `resolve-sync-memory.sh` then do on the batch path what they do
on a bare retry: a failure that wrote only projections of approved lines keeps
the approval, a merge preparation does not (D53), and the agent's own write to
the store always invalidates it.

**The blank screen sits on both entry points, not in the sync.** An
all-whitespace approval is fresh by mtime, so it reaches `git commit -F`, which
rejects it as an empty message on an arm that restamps the file — a refusal that
would repeat identically on every later batch. Both `commit-memory.sh` (after
its own `-m`/`-F` write, so the arg path is covered too) and
`memory-commit-batch.sh` call `gitlore_approval_present`, one predicate in
`util.sh`, which is what makes *no summary* mean the same thing on the two
paths. Each orders its screen behind the store's stale-merge guard, for the
reason above.

Freshness is mtime order, so an agent that writes a memory file after the
message file inside one batch gets one visible re-approval request rather than a
lost commit — the same edge any bare retry carries. The handoff flow writes
memory first and the summary only after the user's approval turn, so it does not
meet it.

## Rejected alternatives

**A `Stop` hook to generate the commit message.** Fires on every response turn
rather than at commit intent — noise, and the wrong timing for a confirmation
gate.

**`PostToolUse` on every memory `Write`/`Edit`.** Couples commit preparation to
individual edits instead of to commit intent. (D31's `PostToolBatch` composition
is a different use of the same event: structural placement, no commit
semantics.)

**An interactive prompt inside the `pre-commit` hook.** Blocks non-interactive
commits from CI and scripts; agent-mediated confirmation costs nothing there.

**An in-session diff dump for commit review.** Too noisy in the TUI. The user
reviews the diff in their own git tooling and approves the prose summary.

**A `PreToolUse` hook constraining the agent's git operations.** Belt-and-braces
with real scoping complexity at the CC level. The drift it anticipated did
happen — a direct submodule commit bypassed FR11 — and the fix was a
submodule-side `pre-commit` gate, consistent with the rest of the hook
architecture rather than layered on top of it (D12).

**An exit-code or status-line protocol from `commit-memory.sh`.** The hook would
act on the run's classification of its own failure, which D53 refused for the
stale-merge guard on the cost asymmetry: a misclassified arm keeps an approval
over content no summary covers. Freshness is the store's own answer. (D56)

**Parsing the refusal text for "needs approval again".** Prose as protocol, and
the contradiction between the refusal's wording and what the retry does is
exactly what parsing would have to keep in sync. (D56)

**Deleting the message file on a fix-needed refusal.** Needs the classification
rejected above, and destroys the text the agent would re-present. (D56)

**An `-ef` guard inside `-F`, skipping the rewrite when the operand is the
message file.** Makes the entry point behave differently on one path value,
invisible from its usage line. (D56)

**Freshness checked in the hook before the run, the script unchanged.** Leaves
the entry point minting an approval for any caller that passes it the message
file, so the gate would live in the caller rather than in the script that
commits (D7). (D56)
