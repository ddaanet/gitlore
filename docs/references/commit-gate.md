# The commit gate

The FR11 approval gate: the nudge that opens an episode, the standalone commit
it produces, and the decisions arguing for that shape. FR11 itself and the
conclusions open the node below; this file is what you need while building or
debugging approval. The git hooks and the two callable scripts that carry a
commit or a push out are in
[git-hooks-and-entry-points.md](git-hooks-and-entry-points.md).

- Approval — **D4** the commit message travels by file handshake, and its
  presence is the approval signal · **D12** a submodule-side commit gate backs
  FR11 as defense in depth · **D19** one canonical approval clause, discovered
  externally via a git-config key · **D22** the memory-hygiene checker is a
  repo-local gate, not shipped surface

---

## Mechanism

**`PostToolUse(Bash)` — the commit nudge.** `post-tool-use.sh` watches for the
project's own pre-commit check, configured as `gitlore.precommitCommand` and
matched by command prefix. It fires when that command exited 0, memory is dirty,
and the commit-message file is absent or stale (mtime against the newest memory
file — a content hash is not worth the complexity; an edit that rewrites
identical content re-triggers, which is acceptable noise). On trigger it emits
`additionalContext` asking Claude to summarize the pending memory changes,
present the summary, and write it to the commit-message file **only** after
explicit user approval. That ordering is FR11's gate: the file must not exist
until approval exists.

The nudge fires once per dirty episode. A `gitlore-nudged` marker in the store's
gitdir suppresses a repeat while memory is still dirty and unapproved, and
`gitlore_sync_memory_to_live` clears it once memory is committed. The marker
lives in the gitdir because the hook can write git internals and the agent
cannot — nothing to gitignore.

**`PostToolBatch` — the standalone commit.** `memory-commit-batch.sh` acts on an
intent file the agent wrote as an ordinary edit; `add-tier-batch.sh` is its
sibling on the mount side. The shape is deliberate and shared: the agent writes
a file, a hook does the git — sidestepping both the command sandbox and the
auto-mode classifier, neither of which lets the agent do this work itself.

The standalone commit is the `handoff` plugin's path, not the general one (D16).
The agent writes the approved summary (`.claude/gitlore-memory-message`) and the
trigger (`.claude/gitlore-commit-memory`); `memory-commit-batch.sh` runs
`commit-memory.sh -F <msgfile>`, which commits with the blessed sentinel and
advances local `live` without a parent commit. The trigger is deliberately kept
out of the general agent-facing instructions — the SessionStart orientation, the
nudge, and the gate's block message all describe only the message-file plus
parent-commit path — so an agent not running the handoff skill is never taught
it can force a standalone memory commit.

**Both IPC files are removed only on a complete commit.** A locked repo and an
in-flight merge are expected transients, so on any failure the trigger *and* the
message file stay put and the next batch retries — no agent action, no lost
approval. A trigger with no approved summary is likewise kept, so the commit
completes on its own the moment the summary lands.

## Decisions — D4, D12, D19, D22

Why approval has this shape: how the summary reaches the hook, why the
submodule holds a gate of its own, the wording that carries the approval, and
why the hygiene checker stays repo-local.

**D4 — Commit message via file handshake**

Claude writes a commit message file at the parent working tree's
`.claude/gitlore-memory-message`; the commit hook reads, uses, and deletes it.
Path is resolved by `gitlore_commit_msg_file`, via
`git -C <memory-path> rev-parse --show-superproject-working-tree`, then
`/.claude/gitlore-memory-message`. It sits in the parent working tree rather
than the memory submodule's gitdir so the agent can write it — the gitdir is
write-blocked by the CC sandbox and the auto-mode classifier.

Write timing: the file is created only after the user explicitly approves the
commit summary Claude has presented. The file's presence is the signal that a
memory commit has user approval; absence or staleness blocks pre-commit.

Alternatives rejected:

- **Stop hook:** fires on every response turn, not only before commits —
  unnecessary writes and churn, and no clean trigger for the confirmation
  prompt.
- **Force-write on memory edit:** PostToolUse on every `Write`/`Edit` would
  generate noise and couple commit preparation to individual edits rather than
  commit intent. The chosen trigger (PostToolUse on the configured pre-commit
  command) is a stronger signal of intent with cleaner timing.
- **`claude --print`:** no session context, cannot ask user for confirmation, no
  memory of why edits were made.

**D12 — Submodule-side commit gate (defense in depth for FR11)**

A gate on the **parent** side alone leaves FR11 open on one flank. The parent
`pre-commit` hook reads the magic commit-message file and, finding memory clean
(or no fresh summary), commits or blocks — but the memory submodule is itself an
ordinary git repo, so a commit made *directly inside it*
(`git -C <mempath> commit`, a human `cd <mempath> && git commit`, a script)
meets nothing: no summary, no approval, no handshake — and the parent then
commits over an already-clean submodule.

Two complementary mechanisms close it:

- **Hard gate (load-bearing).** A `pre-commit` hook *inside* the memory
  submodule, emitted by `emit-memory-gate.sh` into
  `git -C <mempath> rev-parse --git-path hooks/pre-commit` (the shared common
  hooks dir, so one emission also covers linked-worktree memory trees — D11
  parity). It admits a commit **only** when the env sentinel
  `GITLORE_MEMORY_COMMIT=1` is present, and blocks otherwise with a
  `$CLAUDECODE`-branched message. Every gitlore-internal commit path exports the
  sentinel: the parent `pre-commit` blessed commit, both `/gitlore:resolve`
  merge commits, and the install initial commit. A naked commit by an agent,
  human, or script never sets it. This makes FR11 a shell-enforced invariant
  (NFR1 "no AI on hot path"; D7 "scripts decide") on *every* commit path, not
  just the parent route.

  An env sentinel — not "fresh magic file present" — because resolve's merge
  commits use git's `MERGE_MSG`, not the magic file, so a file-presence gate
  would block legitimate resolve commits. One sentinel covers all three blessed
  paths uniformly.

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
  carrying the **prohibition** — memory is a gitlore-guarded submodule; never
  commit inside it directly — plus the one-line seamless happy path: writing a
  memory file is an ordinary edit, and committing the *parent* repo is all you
  need, its pre-commit hook recording, gating and pushing memory. The base
  Claude Code memory instructions describe generic "edit files, save facts"
  memory with no review gate, so the agent's default is actively wrong in a
  gitlore repo. The prohibition corrects the model **before** the agent acts,
  and must be front-loaded: it guards an action the agent would otherwise take
  unprompted, so nothing downstream would disclose it in time. The four-step
  persist *procedure* (summarize → approval → write the magic file → commit the
  parent) is deliberately **not** preloaded — a front-loaded recipe reads as a
  process you must run and induces ceremony, such as pausing for approval before
  even writing a memory file, when persistence is meant to be seamless. It
  surfaces just-in-time instead: from `memory-pre-commit`'s own
  `$CLAUDECODE`-branched output when a direct commit is blocked, and from
  `/gitlore:resolve` on divergence.

This is a cleaner variant of the rejected PreToolUse alternative — a submodule
hook consistent with the existing hook architecture, with none of the CC-level
scoping complexity.

**D19 — Memory-approval wording: one canonical clause, discovered externally via
a git-config key**

The FR11 approval prompt — "summarize pending memory changes, present as a
blockquote, get approval" — is needed at four call sites: three inside gitlore
(`post-tool-use.sh`, `memory-commit-batch.sh`, `resolve.sh`'s
`gitlore_sync_memory_to_live`) and a fourth in the `handoff` plugin's
`checkpoint_memory_directive`, a caller in the D16 sense that drives its own
memory commit around gitlore's IPC files. Composed independently, they drift —
the three internal ones did once (2026-07-16, "one prompt fix, three surfaces"),
and a hand-synced copy in a different repo entirely can only drift further.

**The wording is a self-contained block, appended last.**
`reference/memory-approval-clause.txt` holds the body spec — subject line, blank
line, then **one paragraph per changed memory file**, each opening
`**<Kind> <tier>/<slug>:**` with the kind drawn from New, Update, Augment,
Reduce, or Remove — followed by a literal template of three example paragraphs.
A `MEMORY.md`, root or tier, is excluded from the listing: an index line moves
with the fact it points at, so a paragraph for it would restate its neighbour
and put the routing table on the same footing as the facts. Read via
`gitlore_memory_approval_clause()` (`scripts/lib/util.sh`), it is appended at
the end of each call site's message rather than spliced into a sentence: a
template is inherently multi-line, and one line per file could not carry what a
memory commit message is for — what the fact now claims and what moved it.
Shipping the template rather than describing the shape lets the agent copy a
form instead of inferring one, and the bold prefix is what makes the body
scannable in the approval blockquote. The multi-line clause also constrains
emission: a hook that puts it in JSON must build that JSON with `jq --arg`,
since a raw newline inside a hand-written string is invalid. The four sites keep
their distinct framing — a `PostToolUse` nudge, a pending-trigger retry, a
sync-guard refusal, `resolve.sh`'s divergence-path refusal — so what is shared
is the block, not the messages.

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
comment. All four scripts that source `resolve.sh` (`commit-memory.sh`,
`git-hooks/pre-push`, `git-hooks/pre-commit`, `cc-hooks/session-start.sh`)
source `util.sh` first, so `gitlore_memory_approval_clause` is in scope at
`resolve.sh`'s one call site; a defensive `source` line there would break every
caller on a `readonly` redeclaration.

**D22 — The memory-hygiene checker is a repo-local gate, not shipped surface**

`scripts/check-memory-hygiene.py` runs uncached at the head of `just precommit`
(the cache cannot see a fact change through the `memory` gitlink) and checks
prose shape, wikilink targets, reference style and volatile git state across the
store. It stays in gitlore's own `scripts/`; the plugin ships none of it.

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

## Rejected alternatives

**A `Stop` hook to generate the commit message.** Fires on every response turn
rather than at commit intent — noise, and the wrong timing for a confirmation
gate.

**`PostToolUse` on every memory `Write`/`Edit`.** Couples commit preparation to
individual edits instead of to commit intent. The configured pre-commit command
is a far stronger signal with cleaner timing. (D31's `PostToolBatch` composition
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
