# Memory entry points — decisions D16, D20

The callable scripts a caller outside gitlore's process reaches by plugin `bin/`
name — `gitlore-commit` and `gitlore-push`, with `gitlore-merge` in
[merge-and-resolve.md](merge-and-resolve.md) — the `commit` skill that drives
the first, and the `push` skill that drives the second. `commit-memory.sh`
behind `gitlore-commit` is the one path that commits memory (D58): no parent git
operation and no hook does it (D70). `push-memory.sh` does with no parent push
in flight what the `pre-push` hook does inside one, through a body it shares
with that hook; the hook and the gitlink invariant are in
[git-hooks.md](git-hooks.md). The wording of the approval a commit carries is in
[commit-gate.md](commit-gate.md); FR11 itself stays in `design.md`.

- Entry points — **D16** a standalone memory-commit entry point, called with the
  approved summary · **D20** a standalone push entry point the skill calls
  directly, with no trigger file

Who commits memory, **D58** and **D70**, is in
[memory-commit-ownership.md](memory-commit-ownership.md).

---

## Mechanism

### Memory Commit Entry Point

**`commit-memory.sh`**, run as `gitlore-commit` — a callable script (not a git
hook) that commits the memory store and its dirty tiers and advances each
committed store's local `live`, and is the one memory commit path. A parent
commit does not commit memory (D58), so the script is how the FR11 gate is
satisfied: at the interactive moment the user approves the summary. See D16 and
D70.

The summary is read from stdin, the script's only input; an argument is a usage
error. A terminal on stdin, or a summary that is empty or all whitespace, is a
usage error pointing at `/gitlore:commit`, ahead of any store access. Every
summary is one `== <store> ==` section per store with changes, a single store
included, and each section — `memory` for root, a tier's mount name for a tier —
is its store's message, piped verbatim to that store's `git commit` on stdin,
tiers before root. Text outside a section, a store with changes and no section,
a section for a store with nothing to commit or not mounted, or a store named
twice is refused the same way, every refusal ahead of the first commit.
Tier-only root changes — a tier gitlink moving, `MEMORY.md` lines under a tier
prefix — take no section: a commit created at the same time carries them
silently, so beside a `memory` section they ride in root's own commit, and alone
they get a plain commit whose canned message names the tiers
(`Index lines from <tier>, …`), distinct from the merge path's bookkeeping
message. No message file exists at any point. After committing, each store's
local `live` is fast-forwarded to the new commit; the script never prepares or
takes a merge, and a `live` that cannot fast-forward is reported as divergence,
pointing at `/gitlore:merge` or `/gitlore:push`, exit 0 since a fork is
expected; those two fast-forward or merge the branch with `live` before their
remote step. Guards (exit 0): not a gitlore repo / no memory submodule /
submodule worktree absent / nothing to commit. Dirty with the store or any
mounted tier mid-merge → the stale-merge guard's directive (exit 1), ahead of
everything else.

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

**Discovery.** `bin/gitlore-commit` is a thin `exec` of the script, resolved
from its own location; Claude Code puts the plugin's `bin/` on the Bash tool's
PATH, so a caller runs the bare name (D70).

**Shared body.** `gitlore_sync_memory_to_live` (lib) is the
commit-and-advance-live logic: memory's own stale-merge guard → each mounted
tier's stale-merge guard → `gitlore_stage_landed_tiers` (adopting a tier a
previous run committed inside but never recorded, D50) → pin guard
(`gitlore_compose_check_pins`, aborting on an off-pin tier) → down composition
(`gitlore_compose`; rc 1 aborts on a problem in an index file with uncommitted
changes and otherwise reports and continues, rc 2 aborts) → tier sync (D42; each
dirty tier: `add -A`, write its landing record, commit its section, advance its
local `live`, onto composed carrier content) → memory's `add -A` → removing the
landing records → memory's commit (its section, or the canned index message) →
`push . HEAD:live` (ff) → divergence reported. A stale merge state is handed
back to the sub-agent while `MERGE_HEAD` is there, and when a checkout has
cleared it the survivors are classified and repaired, which may mean carrying
straight on ([merge-state-recovery.md](merge-state-recovery.md)).

### Memory Push Entry Point

**`push-memory.sh`** — the sibling of `commit-memory.sh` on the publish side: it
pushes each tier's `live` and then memory's to their own remotes
**without a parent push**, so an agent or skill can satisfy FR8 at a moment when
no parent commit is in flight. See D20.

Takes no arguments — there is nothing to approve, because FR11 gated this
content when it was committed and publishing an already-approved commit adds no
disclosure decision. Guards (exit 0): not a gitlore repo / no memory submodule /
memory worktree absent / memory has no remote of its own once its tiers are out.
Exit 1 carries a message on stderr naming the next action, including a prepared
merge routed to `/gitlore:resolve` when a remote has diverged.

On success it reports what moved, per store — commits published and where
`origin/live` now sits — from remote-tracking refs captured before the push.
Uncommitted changes are named as **not** published rather than left to be
assumed so: a push publishes commits, and the one wrong inference available to
someone who just asked to publish is that dirty work went with it.

**Discovery.** `bin/gitlore-push`, a thin `exec` of the script, exactly as
`bin/gitlore-commit` is (D70).

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
context. The body makes one call — `gitlore-push` — and reads the exit: `0`
relays the report, a non-zero carrying `gitlore: memory merge prepared` loops
through `/gitlore:resolve` and pushes again, any other non-zero is surfaced
verbatim. A store whose remote is ahead exits `0` with a notice naming
`/gitlore:merge`: it has nothing of its own to publish, and the commit the
memory pointer records is already contained in the remote, so the lockstep
holds.

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

## Decisions — D16, D20

Why the entry points have this shape: why each is standalone rather than a mode
of a hook, and why the push skill calls one of them directly. Why no parent git
operation and no hook commits memory is in
[memory-commit-ownership.md](memory-commit-ownership.md).

**D16 — Standalone memory-commit entry point (called with the approved
summary)**

Committing the parent repo is the wrong way to commit memory. A caller that
wants to commit *only* memory at an interactive moment needs a path of its own:
the parent commit drags whatever else is staged (handoff has already
`git add -f`'d its task file). The motivating caller is
`/commit-commands:commit`, which forbids prompting; splitting review from commit
otherwise causes drift or redundant reviews. So an interactive caller
(`handoff`) couples review+commit once, up front, through a standalone entry
point.

The entry point is `scripts/commit-memory.sh`: it commits the dirty memory store
and its dirty tiers and advances local `live` (`push . HEAD:live`) — no parent
commit. Origin push stays with `pre-push`. The commit-and-advance-live body is
one lib function, `gitlore_sync_memory_to_live`, so the intricate divergence
tail has a single implementation.

**Summary-driven, not file-driven.** The script takes the approved summary as
its input, `git commit`-shaped: the caller passes the text with the call and
nothing is written for the script to find, which keeps callers from
reconstructing gitlore-internal paths. The per-commit FR11 approval therefore
rests on the *caller's* contract — the interactive caller obtains explicit user
approval before invoking. A blessed interactive entry point trusting its
caller's approval is the intended split, not a hole. A caller decides whether
gitlore manages memory here from the memory submodule registration in
`.gitmodules` (the same gate `pre-push` uses), not from the presence of a
command. Caller wiring is out of scope for the gitlore side: `handoff` consumes
the entry point in its own work; `/commit-commands:commit` stays untouched until
there is a second real caller.

**D20 — Standalone push entry point, invoked directly by the skill rather than
through a trigger file**

Memory `live` advances locally on every memory commit, but nothing reaches a
remote until a parent `git push` runs `pre-push`. A commit that no parent git
operation carries (D16, D58) makes that gap routine rather than rare: a session
can commit memory at an interactive moment and end without any parent push,
leaving every fact in the local clone only. `push-memory.sh` closes it, and the
split with `pre-push` is a shared body in the lib with the guards specific to
each caller.

**Why the skill calls the script directly.** Both entry points are called
directly (D70). The classifier's objection to a submodule push does not survive
an explicit `/gitlore:push`: the action *is* what the user asked for. If a call
is denied anyway, nothing has happened — no ref moved, no merge prepared — so
recovery is one turn (re-run behind a `!` prefix). A trigger file would buy
nothing against that, and would add an IPC file, a hook and a stranded-trigger
check; the commit makes the same argument, because the summary it carries is in
the transcript the agent holds.

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

## Rejected alternatives

**Triggering a memory commit through a parent commit** (pointer bump,
`--allow-empty`, or unstaging everything else). All of them fight the parent
commit's requirement of a pointer to record and the gitlink-staging wrinkle, and
drag whatever else is staged. The standalone entry point sidesteps all of it
(D16), and D58 retired the hook that carried the commit.

**Reimplementing the sentinel, `push HEAD:live` and merge-state logic in a
caller.** Fragile duplication of gitlore internals that would drift from the
shared body. The logic stays in `commit-memory.sh`; callers run `gitlore-commit`
(D16, D70).

**A caller that pre-writes the commit-message file, with the entry point only
validating freshness.** Couples external callers to a gitlore-internal path and
keeps two approval semantics alive. A summary passed with the call gives callers
one `git commit`-shaped contract (D16, D70).

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
