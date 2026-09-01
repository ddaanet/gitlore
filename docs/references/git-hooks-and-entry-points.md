# Git hooks and entry points — decisions D16, D20, D46

The git hooks that commit and publish memory, and the two callable scripts a
caller outside gitlore's process reaches through a git-config key. The approval
gate these carry out is in [commit-gate.md](commit-gate.md); FR11 itself stays
in `design.md`.

- Entry points — **D16** a standalone, arg-driven memory-commit entry point ·
  **D20** a standalone push entry point the skill calls directly, with no
  trigger file
- The pointer — **D46** a parent commit is never rewritten to re-pin memory; a
  push refused by divergence is resolved and pushed again

---

## Mechanism

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
   silently. `MERGE_HEAD` is excluded, and so is a plain `--amend` on the tip:
   both author a commit now and must pin current memory. An `--amend` at a
   rebase stop is the sharpest replay of all, and it is caught by the
   `rebase-merge` marker, not by anything about the amend. This is a contract:
   a marker added to the list must be a replay of an earlier commit, never a
   rewrite of the tip.
2. **Guard on a stale merge state** — hand the prepared merge back to the
   sub-agent while `MERGE_HEAD` is there, and when a checkout has cleared it,
   classify what survives and repair, which may mean carrying straight on
   ([merge-state-recovery.md](merge-state-recovery.md)).
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

### The gitlink and `live`

**The gitlink a parent commit records is always an ancestor of memory's
`live`, or `live` itself.** `pre-commit` makes it `live` itself: step 5 stages
the commit step 4 just advanced `live` to. Every path that advances memory
without a parent commit — the `SessionStart` fast-forward, `commit-memory.sh`,
`/gitlore:merge`, a resolved merge — moves `live` forward and leaves the
gitlink behind as an ancestor; a `head-vs-remote` merge in particular keeps the
pending commit reachable as its second parent (D6). A gitlink behind memory's
HEAD is therefore the resting state — ` M memory` in the parent's porcelain —
not drift: it floats, the next parent commit records the move, and nothing
walks memory back to it. `SessionStart` runs `submodule update` on memory only
when its worktree is absent; the pin-to-the-gitlink discipline (D43) is for
tiers inside memory, not for memory in the parent.

The invariant is what NFR5 rests on, and it survives any number of merge
rounds. A push of `live` publishes every ancestor, so `origin/live` contains
the gitlink the moment that push succeeds, and `pre-push` orders memory before
the parent, so a parent push that goes through implies its gitlink is public. A
push refused by divergence is therefore resolved and pushed again, however many
times `origin/live` moves while a merge is under review; the parent commit —
tagged or not — is never rewritten to name the merged memory (D46).

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

## Decisions — D16, D20, D46

Why the entry points have this shape: why each is standalone and arg-driven
rather than a mode of the hook, and why the push skill calls one directly; and
why a parent commit whose push was refused is never amended to catch up with
memory.

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

**D46 — A parent commit is never rewritten to re-pin memory; a push refused by
divergence is resolved and pushed again**

The case that raised it is a release: a toolkit's `release` recipe commits a
version bump — `pre-commit` pins memory into that commit — tags it, and pushes.
`pre-push` publishes memory first, and if any store's `origin/live` moved since
the commit it prepares a merge and refuses, leaving the commit and tag local.
The window is human-paced — the FR11 approval on the release commit and the
review of the merge both sit inside it — and it reopens whenever `origin/live`
moves again while a merge waits for review, so the refusal can repeat.

The considered repair was to `commit --amend` the release commit after the
merge lands so its gitlink names the merged memory, then `tag -f`; step 1's
contract that a tip amend is authored-now would have made the hook re-pin the
gitlink itself. It is refused because the invariant above already gives
correctness: the recorded commit is the merge's second parent, it is published
by the first `live` push that succeeds, and NFR5 holds without the tag's tree
ever naming the merge. What the amend buys is coherence — a tag whose tree names
the memory as merged, and a clean parent tree immediately after — and it costs
a scripted rewrite of a tagged commit, a forced move of a tag about to be
published, and an ordering dependency on step 2's stale-merge guard, which
refuses the amend until the merge is resolved. The loop that replaces it —
resolve, push again, until the push lands — is the one the `push` skill already
runs (D20), and a gitlink behind memory's tip is the same resting state every
other memory advance leaves.

## Rejected alternatives

**Amending a tagged parent commit to re-pin memory after a `pre-push` merge.**
Buys only that the tag's tree names the merged memory; the recorded commit is
already an ancestor of `live` and public on the first successful push. Costs
`tag -f` on an unpublished tag, a rewrite of a tagged commit, and a sequencing
dependency on the stale-merge guard (D46).

**Triggering a memory commit through a parent commit** (pointer bump,
`--allow-empty`, or unstaging everything else). All of them fight the hook's
parent-commit requirement and the gitlink-staging wrinkle, and drag whatever
else is staged. The standalone entry point sidesteps all of it (D16).

**Reimplementing the sentinel, `push HEAD:live` and merge-state logic in a
caller.** Fragile duplication of gitlore internals that would drift from
`pre-commit`. The logic stays in `commit-memory.sh`; callers resolve it via
`gitlore.commitCommand` (D16).

**A caller that pre-writes the commit-message file, with the entry point only
validating freshness.** Couples external callers to a gitlore-internal path and
keeps two approval semantics alive. Arg-driven (`-m`/`-F`) keeps the IPC
handshake internal and gives callers one `git commit`-shaped contract (D16).
