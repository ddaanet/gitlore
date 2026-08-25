# The commit gate

The FR11 approval gate and the two standalone entry points that satisfy it — the
nudge that opens an episode, the git hooks that commit and publish, the two
callable scripts a caller outside gitlore's process reaches through a git-config
key, and the decisions arguing for that shape. FR11 itself and the conclusions
stay in `design.md`; this file is what you need while building or debugging the
commit and publish path.

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

### Git Hooks

Both hooks run in the parent repo's chain, and both begin the same way: capture
`GIT_INDEX_FILE` and any replay state, then clear git's full local-env-var set
(`git rev-parse --local-env-vars`). Git exports those variables scoped to the
*parent*, and a `git -C <submodule>` that inherits them breaks submodule
resolution or, in a linked worktree, silently redirects the submodule's refs and
objects into the parent's store. Both exit 0 when the repo has no
`gitlore-memory` entry, and when the submodule worktree is absent (a
session-less linked worktree) — never block a parent git operation over memory.

**`pre-commit`** commits memory and moves the pointer, in this order:

1. **Stand down during a replay.** A rebase, cherry-pick or revert re-creates
   commits authored earlier while the memory worktree stays put, so syncing
   would re-pin a historical commit to today's memory. Detected via
   `--git-path rebase-merge|rebase-apply|CHERRY_PICK_HEAD|REVERT_HEAD` before
   the env unset (replay state is per-worktree), announced rather than skipped
   silently. `MERGE_HEAD` is excluded: a merge commit is authored now and must
   pin current memory.
2. **Refuse to proceed over a stale merge state** (abort-then-retry, or manual
   intervention when `MERGE_HEAD` is already gone).
3. **Sync every dirty tier** and advance each tier's local `live`, so the
   gitlink the memory commit is about to record has already moved (D42).
4. **Sync memory** through the shared `gitlore_sync_memory_to_live`: the FR11
   dirty/freshness gate, `add -A`,
   `GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>`, remove the message file, then
   `push . HEAD:live` fast-forward-only. Divergence prepares a merge and yields
   (`gitlore_yield_merge`), exiting 1.
5. **Stage the gitlink** into the index git handed the hook — the captured
   `GIT_INDEX_FILE`, restored for that one `git add`, because a bare `add`
   misses the `-a` and pathspec index flavors and dies on `index.lock` under
   them.

Every refusal branches on `$CLAUDECODE`: agent-facing text naming the next
action, user-facing text directing them to open the project in Claude Code.

**`pre-push`** publishes in the same before-and-alongside order: each tier's
`live` to its own remote, then memory's. Failure is fatal — a tier that silently
stops publishing is indistinguishable from one with nothing to say. The
memory-absent skip stays non-blocking but warns when the gitlink about to be
published is not reachable on the memory remote, decided locally without a
fetch. Divergence routes to `/gitlore:resolve`, which diagnoses the flavor.

### Memory Commit Entry Point

**`commit-memory.sh`** — a callable script (not a git hook) that commits the
memory submodule and advances local `live` **without a parent commit**, so a
skill can satisfy the FR11 gate at an interactive moment and a later
non-interactive parent commit never trips it. See D16.

Arg-driven, `git commit`-style: `-m <summary>`, `-F <file>`, or `-F -`
(stdin/heredoc). It resolves the memory path, writes the summary to the
commit-msg file, then calls the shared `gitlore_sync_memory_to_live`. Guards
(exit 0): not a gitlore repo / no `gitlore-memory` submodule / submodule
worktree absent / memory clean-and-synced. Dirty with no summary supplied → exit
1 with a caller-facing message.

**Discovery.** `gitlore.commitCommand` resolves to
`$PLUGIN_ROOT/scripts/commit-memory.sh`, so a caller finds the script with one
lookup and no coupling to gitlore's internal layout (D5, D16).

**Shared body.** `gitlore_sync_memory_to_live` (lib) is the
commit-and-advance-live logic factored out of `pre-commit`: dirty/freshness gate
→ `add -A` → `GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>` → `rm <msgfile>` →
`push . HEAD:live` (ff) → divergence (prepare / write merge-state / emit
directive / exit 1). Both `pre-commit` and `commit-memory.sh` call it — one
implementation, no drift.

### Memory Push Entry Point

**`push-memory.sh`** — the sibling of `commit-memory.sh` on the publish side: it
pushes each tier's `live` and then memory's to their own remotes
**without a parent push**, so an agent or skill can satisfy FR8 at a moment when
no parent commit is in flight. See D20.

Takes no arguments — there is nothing to approve, because FR11 gated this
content when it was committed and publishing an already-approved commit adds no
disclosure decision. Guards (exit 0): not a gitlore repo / no `gitlore-memory`
submodule / memory worktree absent / memory has no remote of its own once its
tiers are out. Exit 1 carries a message on stderr naming the next action,
including a prepared merge routed to `/gitlore:resolve` when a remote has
diverged.

On success it reports what moved, per store — commits published and where
`origin/live` now sits — from remote-tracking refs captured before the push.
Uncommitted changes are named as **not** published rather than left to be
assumed so: a push publishes commits, and the one wrong inference available to
someone who just asked to publish is that dirty work went with it.

**Discovery.** `gitlore.pushCommand`, seeded at install and re-pinned every
`SessionStart`, exactly as `gitlore.commitCommand` is (D5, D16).

**Shared body.** `gitlore_push_stores` (lib) is the tier-then-memory publish
logic factored out of `pre-push`: memory's stale-merge guard → per tier
(checkout guard, `live` guard, remote check, stale-merge guard, fetch, ff push,
divergence → yield) → memory's remote check → memory fetch → memory push →
unreachable-vs-refused discrimination → divergence yield. Both `pre-push` and
`push-memory.sh` call it, so the tier-before-memory ordering that FR8 rests on
cannot drift between them; `pre-push` keeps only what is its own, the
session-less-worktree warning about an unpublished gitlink.

**A memory store with no remote publishes its tiers anyway.** A local-only
install is a supported end state, and such a repo can still mount a shared tier,
which is then the only store anyone else reads. So memory's own remote is
checked *after* the tier loop, and its absence is a notice on stderr with exit 0
rather than a failure: letting it withhold the tiers would keep the shared half
of the store local for a reason that does not apply to it.

> **The placeholder url is a marker, not an address.** `GITLORE_PLACEHOLDER_URL`
> (`./.git/gitlore-placeholder`) exists because git refuses to initialize a
> submodule entry carrying no url at all
> (`fatal: No url found for submodule path`), and because an absent key would be
> indistinguishable from a malformed entry, where this value names the slot as
> gitlore's to fill later. It does not make a clone work —
> `submodule update --init` fails on it exactly as it fails without a url, just
> with a different message. It reaches the store's own `remote.origin.url` by
> one route only, a `git submodule sync`, and arrives *absolutized* against
> wherever the superproject lives, never in the registered spelling. So every
> remote check compares through `gitlore_is_placeholder_url`, which matches both
> spellings, and treats a match as no remote: for the push and merge paths that
> means memory stays local rather than earning a network diagnosis, and for
> `create-remote.sh` it means the slot is still free — which also obliges it to
> `remote set-url` rather than `remote add`, since origin exists.

### The `push` skill

Publish every store to its own remote with no parent push. Front door is
`/gitlore:push`, but it is a skill rather than a command because its second
entry is contextual: a session that committed memory and will make no parent
push has to reach for it unprompted, and only a description is matched against
context. The body makes one call — `bash "$(git config gitlore.pushCommand)"` —
and reads the exit: `0` relays the report, a non-zero carrying
`gitlore: memory merge prepared` loops through `/gitlore:resolve` and pushes
again, any other non-zero is surfaced verbatim. A store whose remote is ahead
exits `0` with a notice naming `/gitlore:merge`: it has nothing of its own to
publish, and the commit the memory pointer records is already contained in the
remote, so the lockstep holds.

Every store is checked for HEAD and `live` naming the same commit *before*
anything is published — the push sends `live` while the enclosing commit's
gitlink records HEAD, so a store whose refs disagree either publishes something
other than what its pointer names or is refused on a ref no diagnosis downstream
looks at. That drift is reported with both shas and the remedy for its
direction, never repaired: which ref was intended is not recoverable from the
refs. There is no approval step; FR11 gated the content at commit time.

## Decisions — D4, D8, D12, D16, D19, D20, D22

**D4 — Commit message via file handshake**

Claude writes a commit message file at the parent working tree's
`.claude/gitlore-memory-message`; the commit hook reads, uses, and deletes it.
Path is resolved via
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

**D8 — Remote creation requires explicit user confirmation**

Creating a remote repository is a visible external action with side effects
outside the local machine (namespace occupancy, provider-side records,
potentially public visibility). Even when `gh` CLI is available and parameters
are straightforward, the agent presents the full proposal — name, owner,
visibility, creation method — and waits for explicit approval before executing.

This confirmation is distinct from the install-time disclosure, which is
informational orientation. D8 gates the specific external action. Rationale:
external actions are not covered by the per-commit review gate and require their
own opt-in.

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

**D16 — Standalone memory-commit entry point (arg-driven)**

The only blessed path to commit memory is committing the parent repo, which
fires `pre-commit` (sentinel commit + advance `live`). That is wrong for a
caller that wants to commit *only* memory at an interactive moment so a later
non-interactive commit never trips the FR11 gate: the parent commit drags
whatever else is staged (handoff has already `git add -f`'d its task file), and
a naked submodule commit is blocked by the D12 gate. The motivating caller is
`/commit-commands:commit`, which forbids prompting; splitting review from commit
otherwise causes drift or redundant reviews. So an interactive caller
(`handoff`) couples review+commit once, up front, through a standalone entry
point.

The entry point is `scripts/commit-memory.sh`: it commits the dirty memory
submodule with the `GITLORE_MEMORY_COMMIT=1` sentinel and advances local `live`
(`push . HEAD:live`) — no parent commit. Origin push stays with `pre-push`. The
commit-and-advance-live body it shares with `pre-commit` is factored into one
lib function, `gitlore_sync_memory_to_live`; both callers invoke it, so the
intricate divergence tail has a single implementation.

**Arg-driven, not file-driven.** The script takes the approved summary as an
argument (`-m`, `-F <file>`, `-F -`), mirroring `git commit`, and writes it to
the commit-msg file itself. The message file stays purely the hook↔commit IPC
handshake (D4) rather than becoming the caller's contract, which keeps callers
from reconstructing gitlore-internal paths. The freshness gate stays *inside*
the shared body because `pre-commit` still needs it to refuse un-approved
commits; on the script's path it is satisfied by construction (the summary is
written immediately before the commit, so the mtime check always passes). The
per-commit FR11 approval therefore rests on the *caller's* contract here — the
interactive caller obtains explicit user approval before invoking — while the
mtime gate continues to protect the non-interactive parent path. A blessed
interactive entry point trusting its caller's approval is the intended split,
not a hole.

**Discovery via `gitlore.commitCommand`.** Seeded at install in
`write-settings.sh` and re-pinned to `$PLUGIN_ROOT/scripts/commit-memory.sh`
every `SessionStart` — the self-healing re-pin that absorbs plugin-cache path
changes exactly as `gitlore.hooksDir` does (D5) — so existing repos pick the key
up on their next session, with no reinstall. The key is a
*path pin, not an activation signal*: a caller decides whether gitlore manages
memory here from the `gitlore-memory` submodule registration in `.gitmodules`
(FR12 — the same gate `pre-commit` uses, never stale), not from the presence of
the key. It only answers *where* the script is, and a caller should still verify
the resolved path is executable and degrade with a "restart your session" hint
rather than exec a missing path (the D5 staleness window). Caller wiring is out
of scope for the gitlore side: `handoff` consumes the key in its own work;
`/commit-commands:commit` stays untouched until there is a second real caller.

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

**D20 — Standalone push entry point, invoked directly by the skill rather than
through a trigger file**

Memory `live` advances locally on every memory commit, but nothing reaches a
remote until a parent `git push` runs `pre-push`. The standalone commit path
(D16) made that gap routine rather than rare: a session can commit memory at an
interactive moment and end without any parent push, leaving every fact in the
local clone only. `push-memory.sh` closes it, and the split with `pre-push` is
the same one `commit-memory.sh` has with `pre-commit` — the shared body in the
lib, the entry-point-specific guards at each caller.

**Why the skill calls the script directly, unlike the standalone commit.** The
commit path routes through an IPC file and a `PostToolBatch` hook because the
auto-mode classifier refuses agent writes it reads as self-configuration, and
because a denial there strands a summary the user already approved — the
approval is the expensive, unrepeatable thing. Push has no approval to lose, and
the classifier's objection to a submodule push does not survive an explicit
`/gitlore:push`: the action *is* what the user asked for. If a call is denied
anyway, nothing has happened — no ref moved, no merge prepared — so recovery is
one turn (re-run behind a `!` prefix) rather than a lost gate. A trigger file
would buy nothing against that, and would add a second IPC file, hook and
stranded-trigger check.

**Push is not fire-and-forget, and the skill is shaped around that.** A refused
push whose reason git attributes to divergence prepares a merge and yields,
which dispatches the memory-merger sub-agent and lands a merge commit under its
own approval gate. Divergence is therefore a first-class outcome in the skill
body, not an error branch: resolve, then **push again**, because tiers publish
before memory and resolve handles one store per pass, so a second store can
still be unpublished when the first one's merge lands. That loop, not the exit
code alone, is what makes "published" true.

**No approval gate of its own.** FR11 gates what enters the history, applied
where content is composed. Re-asking at publish time would gate a decision
already made and train the user to approve a prompt carrying no new information
— the failure mode that makes a gate ornamental. What the run owes the user is
an accurate report: which stores moved, how far, and — named explicitly rather
than left to inference — that uncommitted changes did not go with them.

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
