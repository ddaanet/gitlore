# Memory entry points — decisions D16, D20, D58

The two callable scripts a caller outside gitlore's process reaches through a
git-config key — `commit-memory.sh` and `push-memory.sh` — and the `push` skill
that drives the second. `commit-memory.sh` is the one path that commits memory
(D58): no parent git operation does it. `push-memory.sh` does with no parent
push in flight what the `pre-push` hook does inside one, through a body it
shares with that hook; the hook and the gitlink invariant are in
[git-hooks.md](git-hooks.md). The approval gate a commit carries out is in
[commit-gate.md](commit-gate.md); FR11 itself stays in `design.md`.

- Entry points — **D16** a standalone, arg-driven memory-commit entry point ·
  **D20** a standalone push entry point the skill calls directly, with no
  trigger file · **D58** a memory commit is the agent's own act, never a side
  effect of a parent commit

---

## Mechanism

### Memory Commit Entry Point

**`commit-memory.sh`** — a callable script (not a git hook) that commits the
memory submodule and advances local `live`, and is the one memory commit path. A
parent commit does not commit memory (D58), so the script is how the FR11 gate
is satisfied: at the interactive moment the user approves the summary. See D16.

Arg-driven, `git commit`-style: `-m <summary>`, `-F <file>`, or `-F -`
(stdin/heredoc). It resolves the memory path, writes the summary to the
commit-msg file, then calls the shared `gitlore_sync_memory_to_live`. Invoked
**bare**, it writes nothing and commits on the approval already on disk, judged
by that shared body's freshness gate — the form `memory-commit-batch.sh` uses
(D56, in [commit-gate.md](commit-gate.md)). Guards (exit 0): not a gitlore repo
/ no `gitlore-memory` submodule / submodule worktree absent / memory
clean-and-synced. Dirty with the approval absent or blank → exit 1 with a
caller-facing message; dirty with a stale one → the sync's own refusal; dirty
with the store or any mounted tier mid-merge → the stale-merge guard's
directive, which runs ahead of both (see [commit-gate.md](commit-gate.md)).

**The pointer is staged by the commit.** After a run that moved memory's HEAD,
the script stages the memory gitlink in the parent index, so the next parent
commit records the pointer with no hook. A run that moved nothing stages
nothing. Staging is skipped, with a notice, while the parent is in a rebase,
cherry-pick or revert: a replay re-creates commits authored earlier while the
memory worktree stays put, so staging would re-pin a historical commit to
today's memory (detected from `--git-path rebase-merge|rebase-apply|
CHERRY_PICK_HEAD|REVERT_HEAD`; `MERGE_HEAD` is absent, a merge being authored
now). A `git add` that fails is reported and the script still exits 0: the
memory commit landed, and the pointer floats until staged.

**Discovery.** `gitlore.commitCommand` resolves to
`$PLUGIN_ROOT/scripts/commit-memory.sh`, so a caller finds the script with one
lookup and no coupling to gitlore's internal layout (D5, D16).

**Shared body.** `gitlore_sync_memory_to_live` (lib) is the
commit-and-advance-live logic: memory's own stale-merge guard → dirty/freshness
gate (a store with no fresh approval first meets any tier's prepared-merge
directive, then the summary request) → each mounted tier's stale-merge guard →
`gitlore_stage_landed_tiers` (adopting a tier a previous run committed inside
but never recorded, D50) → pin guard (`gitlore_compose_check_pins`, aborting on
an off-pin tier) → down composition (`gitlore_compose`; rc 1 aborts on a problem
in an index file with uncommitted changes and otherwise reports and continues,
rc 2 aborts) → tier sync (D42; each dirty tier: `add -A`, write its landing
record, commit, advance its local `live`, onto composed carrier content) →
memory's `add -A` → removing the landing records →
`GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>` → `rm <msgfile>` →
`push . HEAD:live` (ff) → divergence (prepare / write merge-state / emit
directive / exit 1). A stale merge state is handed back to the sub-agent while
`MERGE_HEAD` is there, and when a checkout has cleared it the survivors are
classified and repaired, which may mean carrying straight on
([merge-state-recovery.md](merge-state-recovery.md)).

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
looks at. One direction is repaired rather than reported: a `live` strictly
behind a HEAD that contains it is a ref that failed to keep up — the store rests
detached *at* `live`, and every commit in HEAD reached it through a gate — so
the preflight advances it with a local ff-checked `push . HEAD:live`, says which
store it moved, and publishes. Asking for that one command back would be a
round-trip with nothing to decide. Any other drift is reported with both shas
and the remedy for its direction and nothing moves: which ref was intended is
not recoverable from the refs. There is no approval step; FR11 gated the content
at commit time.

## Decisions — D16, D20, D58

Why the entry points have this shape: why each is standalone and arg-driven
rather than a mode of a hook, why the push skill calls one of them directly, and
why no parent git operation commits memory.

**D16 — Standalone memory-commit entry point (arg-driven)**

Committing the parent repo is the wrong way to commit memory. A caller that
wants to commit *only* memory at an interactive moment needs a path of its own:
the parent commit drags whatever else is staged (handoff has already
`git add -f`'d its task file), and a naked submodule commit is blocked by the
D12 gate. The motivating caller is `/commit-commands:commit`, which forbids
prompting; splitting review from commit otherwise causes drift or redundant
reviews. So an interactive caller (`handoff`) couples review+commit once, up
front, through a standalone entry point.

The entry point is `scripts/commit-memory.sh`: it commits the dirty memory
submodule with the `GITLORE_MEMORY_COMMIT=1` sentinel and advances local `live`
(`push . HEAD:live`) — no parent commit. Origin push stays with `pre-push`. The
commit-and-advance-live body is one lib function, `gitlore_sync_memory_to_live`,
so the intricate divergence tail has a single implementation.

**Arg-driven, not file-driven.** The script takes the approved summary as an
argument (`-m`, `-F <file>`, `-F -`), mirroring `git commit`, and writes it to
the commit-msg file itself. The message file stays purely the hook↔commit IPC
handshake (D4) rather than becoming the caller's contract, which keeps callers
from reconstructing gitlore-internal paths. The freshness gate stays *inside*
the shared body because the bare retry needs it to refuse un-approved commits;
on the script's arg path it is satisfied by construction (the summary is written
immediately before the commit, so the mtime check always passes). A **bare**
invocation supplies no summary and writes nothing, so the same gate judges the
approval file as it stands: fresh commits, stale refuses, and absent or blank
refuses ahead of the sync with this entry point's own directive — behind the
stale-merge guard, which the script runs first so a prepared merge is never
answered with a request for a summary. That is the form a gitlore-internal
caller retrying a deferred commit uses, because an approval it did not just
obtain is not one it can bless (D56, in [commit-gate.md](commit-gate.md)). The
per-commit FR11 approval on the arg path therefore rests on the *caller's*
contract — the interactive caller obtains explicit user approval before invoking
— while the mtime gate continues to protect the non-interactive trigger-file
path. A blessed interactive entry point trusting its caller's approval is the
intended split, not a hole.

**Discovery via `gitlore.commitCommand`.** Seeded at install in
`write-settings.sh` and re-pinned to `$PLUGIN_ROOT/scripts/commit-memory.sh`
every `SessionStart` — the self-healing re-pin that absorbs plugin-cache path
changes exactly as `gitlore.hooksDir` does (D5) — so existing repos pick the key
up on their next session, with no reinstall. The key is a
*path pin, not an activation signal*: a caller decides whether gitlore manages
memory here from the `gitlore-memory` submodule registration in `.gitmodules`
(FR12 — the same gate `pre-push` uses, never stale), not from the presence of
the key. It only answers *where* the script is, and a caller should still verify
the resolved path is executable and degrade with a "restart your session" hint
rather than exec a missing path (the D5 staleness window). Caller wiring is out
of scope for the gitlore side: `handoff` consumes the key in its own work;
`/commit-commands:commit` stays untouched until there is a second real caller.

**D20 — Standalone push entry point, invoked directly by the skill rather than
through a trigger file**

Memory `live` advances locally on every memory commit, but nothing reaches a
remote until a parent `git push` runs `pre-push`. A commit that no parent git
operation carries (D16, D58) makes that gap routine rather than rare: a session
can commit memory at an interactive moment and end without any parent push,
leaving every fact in the local clone only. `push-memory.sh` closes it, and the
split with `pre-push` is a shared body in the lib with the guards specific to
each caller.

**Why the skill calls the script directly, unlike the trigger-file commit.** The
commit path keeps an IPC file and a `PostToolBatch` hook beside the direct call
because the auto-mode classifier refuses agent writes it reads as
self-configuration, and because a denial there strands a summary the user
already approved — the approval is the expensive, unrepeatable thing. Push has
no approval to lose, and the classifier's objection to a submodule push does not
survive an explicit `/gitlore:push`: the action *is* what the user asked for. If
a call is denied anyway, nothing has happened — no ref moved, no merge prepared
— so recovery is one turn (re-run behind a `!` prefix) rather than a lost gate.
A trigger file would buy nothing against that, and would add a second IPC file,
hook and stranded-trigger check.

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

**D58 — A memory commit is the agent's own act, never a side effect of a parent
commit**

`commit-memory.sh` — directly, or through the trigger file
`memory-commit-batch.sh` acts on — is the one commit path. The parent
`pre-commit` hook, its wiring and the `precommitCommand` nudge are retired, and
a parent `git commit` no longer touches memory.

**Why the hook went.** A parent commit over dirty memory met the FR11 approval
gate inside a git hook, which has no one to converse with: the refusal reached
whoever ran `git commit`, and a subagent's commits blocked on a summary only the
main conversation could obtain. The approval is a conversation, and a
conversation belongs to the agent that holds the user; a hook can only refuse
and hand the request back. With the commit made where the approval is obtained,
the hook has no work the script does not do.

**The pointer is staged by the commit.** The hook's last step staged the moved
gitlink into the index git handed it. The script stages it into the parent index
after a run that moved memory's HEAD, so the next parent commit records it with
no hook; between the memory commit and that parent commit the gitlink floats
(git-hooks.md). During a replay (rebase, cherry-pick, revert) the script skips
the staging and says so, because a replayed commit must keep the pointer it
recorded. FR11's approval stays: summarize, ask, then commit.

**Hook-manager configs are a published boundary; `.git/hooks/pre-commit` is
not.** A tracked `lefthook.yml`, `.husky/pre-commit` or `.overcommit.yml`
written by an earlier install names `gitlore-pre-commit` and travels to every
clone, so the installer cannot assume it was rewritten: `gitlore-pre-commit`
stays in the common dir as an exit-0 stub, and new wiring installs `pre-push`
only. The direct wiring wrote a file in the clone's own `.git/hooks`, which no
one else reads; `wire-direct.sh` removes that shim when it is byte-for-byte what
it wrote, strips the appended gitlore block from a hand-rolled hook, and leaves
any other `pre-commit` hook alone. `write-settings.sh` deletes a leftover
`gitlore.precommitCommand`.

## Rejected alternatives

**Triggering a memory commit through a parent commit** (pointer bump,
`--allow-empty`, or unstaging everything else). All of them fight the parent
commit's requirement of a pointer to record and the gitlink-staging wrinkle, and
drag whatever else is staged. The standalone entry point sidesteps all of it
(D16), and D58 retired the hook that carried the commit.

**Reimplementing the sentinel, `push HEAD:live` and merge-state logic in a
caller.** Fragile duplication of gitlore internals that would drift from the
shared body. The logic stays in `commit-memory.sh`; callers resolve it via
`gitlore.commitCommand` (D16).

**A caller that pre-writes the commit-message file, with the entry point only
validating freshness.** Couples external callers to a gitlore-internal path and
keeps two approval semantics alive. Arg-driven (`-m`/`-F`) keeps the IPC
handshake internal and gives callers one `git commit`-shaped contract (D16).

**The hook standing down on a missing approval.** Keeps the hook, its wiring,
the index capture and the replay guard alive for one case, and a refusing
`pre-commit` can abort a rebase. (D58)
