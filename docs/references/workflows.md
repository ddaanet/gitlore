# Workflows

The step lists for every path a user or the agent walks: the commit and push
happy paths, a tier write, publishing without a parent push, taking without
publishing, the two resolve entries, clone, and worktree creation. The
conclusions and the component map stay in `design.md`; this file is the sequence
each component runs in.

---

**Commit (happy path, agent-driven)**

1. Claude edits memory files during the session (ambiently, throughout).
2. When the work is ready to commit, Claude summarizes the pending memory
   changes in prose and presents the summary. The user reviews the full diff in
   their own git tooling if they wish, then gives explicit confirmation.
3. Claude runs `gitlore-commit` through the `gitlore:commit` skill with the
   confirmed summary on stdin, one `== <store> ==` section per changed store
   (D70). The preceding confirmation covers the commit itself.
4. The script commits every dirty tier with its section and advances each tier's
   `live`, then commits memory with its section, and ff-pushes `HEAD` → `live`.
5. The script stages the memory gitlink in the parent index (skipped, with a
   notice, during a rebase, cherry-pick or revert).
6. Claude commits the parent as usual. The commit touches no memory; it records
   the pointer the script staged (D58).

**Push (happy path)**

1. User or Claude runs `git push`. Agent-initiated push is allowed under the
   auto permission mode (subject to user approval of that mode).
2. pre-push hook: pushes each tier's `live` to its own remote, then memory
   `live` → `origin/live`.
3. Parent push proceeds.

**Tier write**

A portable fact authored into `memory/<tier>/` rides the ordinary memory commit:
the tier is committed and its `live` advanced before memory's own `add -A`, so
the memory commit records the moved gitlink rather than lagging it, and the tier
is pushed before memory is. One approval summary covers the whole episode,
grouped by destination — a line bound for a shared tier is more public than one
bound for project memory.

**Publish without a parent push**

1. The user runs `/gitlore:push`, or a session that committed memory is ending
   with no parent push in sight.
2. The skill runs `gitlore-push`.
3. Each tier's `live` goes to its own remote, then memory's — the same order
   `pre-push` uses, from the same shared body.
4. A store whose remote is ahead is taken in the run — fast-forward, then the
   end compose and one bookkeeping commit — rather than left as a
   `/gitlore:merge` errand (D49).
5. The skill relays which stores moved and how far, which were taken, and names
   any uncommitted memory as unpublished.
6. On divergence: `/gitlore:resolve` merges the store that diverged, then the
   skill pushes again, until the command exits 0.

**Take without publishing**

1. The user runs `/gitlore:merge`, or a session start reported commits on `live`
   not checked out here, upstream memory commits, or a tier whose remote is
   ahead.
2. The skill runs `gitlore-merge`.
3. Each tier is taken first, then memory's own store, and root's index is
   written once at the end (D77 in [take-and-compose.md](take-and-compose.md)).
   For memory's own store a local `live` ahead of `HEAD` is taken first: a clean
   store is checked out at `live`, a dirty one is reported and left (D59).
4. The end of the run commits the moved gitlinks and recomposed root index in
   one canned bookkeeping message (D49), leaving the store clean; a root store
   holding unapproved work keeps the moves staged instead, and the run says
   which.
5. On divergence: `/gitlore:resolve`, with a merge marked not-to-publish; the
   skill reconciles again until the command exits 0. Nothing is published.

**Resolve (on divergence) — primary path: agent-driven**

Most divergence is detected while the agent is attempting a take or a push. The
agent sees the exit-1 stderr of `merge-memory.sh`, `push-memory.sh` or the
`pre-push` hook (addressed to it via the `$CLAUDECODE` branch) and invokes
`/gitlore:resolve` inline without user intervention; a memory commit that forks
from `live` exits 0 and reports it, naming `/gitlore:merge` and `/gitlore:push`;
the skill's five steps are in [merge-and-resolve.md](merge-and-resolve.md). It
ends by advancing `live` — and, for a remote-flavored merge, `origin/live` —
leaving HEAD detached at the new `live`, refreshing the parent's context with
the incoming diff (or directing the user to `/clear` when resolve ran at session
start), and retrying the original take or push.

**Resolve fallback: user-driven**

If divergence surfaces outside a Claude session (`git push` run from a plain
terminal), the hook's stderr directs the user to open this project in Claude
Code and run `/gitlore:resolve`. The primary path resumes from there.

**Clone**

`git clone --recurse-submodules <repo>` → the first `SessionStart` configures
settings, reports where memory stands, and replays the hook-manager sentinel.

Without `--recurse-submodules`: `SessionStart` detects the uninitialized
submodule and runs `git submodule update --init`. That leaves the memory
submodule at a **detached HEAD** on the recorded gitlink SHA with only the
remote-tracking `origin/live` — no local branches. Since the branch-model logic
references `live` as a *local* ref (the detach target and the report's
comparison point), `SessionStart` first materializes a local `live` from the
checked-out `HEAD` — the gitlink commit, whether or not `origin/live` exists and
never `origin/live`, which may be ahead of it (D59) — then proceeds as above.
Without it the first post-clone session dies on `fatal: 'live' is not a commit`.

**Worktree creation** — `SessionStart` in the new worktree initializes the
memory submodule worktree, detached at `live`. Uniform across
`claude --worktree`, manual `git worktree add`, and the Desktop button (all
start a session in the worktree). Why no `WorktreeCreate` hook is registered is
in [session.md](session.md).
