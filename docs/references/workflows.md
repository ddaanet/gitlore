# Workflows

The step lists for every path a user or the agent walks: the commit and push
happy paths, a tier write, publishing without a parent push, taking without
publishing, the two resolve entries, clone, and worktree creation. The
conclusions and the component map stay in `design.md`; this file is the sequence
each component runs in.

---

**Commit (happy path, agent-driven)**

1. Claude edits memory files during the session (ambiently, throughout).
2. When preparing to commit, Claude runs the configured pre-commit command as
   part of its workflow (via `Bash`).
3. PostToolUse hook fires — memory is dirty, commit-msg absent or stale.
4. Claude summarizes pending memory changes in prose and presents the summary.
   The user reviews the full diff in their own git tooling if they wish, then
   gives explicit confirmation.
5. Claude writes the confirmed summary to the commit-msg file.
6. Claude runs `git commit`. The preceding confirmation of the commit message
   covers the commit itself.
7. pre-commit hook: commits every dirty tier and advances each tier's `live`,
   then commits memory with the commit-msg file, deletes the file, and ff-pushes
   `HEAD` → `live`.
8. The hook stages the memory gitlink, so the parent commit records the pointer
   its own hook just created.

**Push (happy path)**

1. User or Claude runs `git push`. Agent-initiated push is allowed under the
   auto permission mode (subject to user approval of that mode).
2. pre-push hook: pushes each tier's `live` to its own remote, then memory
   `live` → `origin/live`.
3. Parent push proceeds.

**Tier write**

A portable fact authored into `memory/<tier>/` rides the ordinary commit flow:
the tier is committed and its `live` advanced before memory's own `add -A`, so
the memory commit records the moved gitlink rather than lagging it, and the tier
is pushed before memory is. One approval summary covers the whole episode,
grouped by destination — a line bound for a shared tier is more public than one
bound for project memory.

**Publish without a parent push**

1. The user runs `/gitlore:push`, or a session that committed memory is ending
   with no parent push in sight.
2. The skill runs `push-memory.sh` through the `gitlore.pushCommand` key.
3. Each tier's `live` goes to its own remote, then memory's — the same order
   `pre-push` uses, from the same shared body.
4. A store whose remote is ahead is taken in the run — fast-forward, adoption,
   bookkeeping commit — rather than left as a `/gitlore:merge` errand (D49).
5. The skill relays which stores moved and how far, which were taken, and names
   any uncommitted memory as unpublished.
6. On divergence: `/gitlore:resolve` merges the store that diverged, then the
   skill pushes again, until the command exits 0.

**Take without publishing**

1. The user runs `/gitlore:merge`, or a session start named a tier whose
   remote is ahead.
2. The skill runs `merge-memory.sh` through the `gitlore.mergeCommand` key.
3. Memory's own remote is taken first, then each tier's — the mirror of the
   publish order (D49 in [merge-and-resolve.md](merge-and-resolve.md)).
4. A tier take commits the moved gitlink and recomposed root index under the
   canned bookkeeping message, leaving the store clean; a root store holding
   unapproved work keeps the pair staged instead, and the run says which.
5. On divergence: `/gitlore:resolve`, with a merge marked not-to-publish; the
   skill reconciles again until the command exits 0. Nothing is published.

**Resolve (on divergence) — primary path: agent-driven**

Most divergence is detected while the agent is attempting commit or push. The
agent sees the hook's exit-1 stderr (addressed to it via the `$CLAUDECODE`
branch) and invokes `/gitlore:resolve` inline without user intervention; the
skill's five steps are in
[merge-and-resolve.md](merge-and-resolve.md). It ends
by advancing `live` — and, for a remote-flavored merge, `origin/live` — leaving
HEAD detached at the new `live`, refreshing the parent's context with the
incoming diff (or directing the user to `/clear` when resolve ran at session
start), and retrying the original commit or push.

**Resolve fallback: user-driven**

If divergence surfaces outside a Claude session (`git commit` or `git push` run
from a plain terminal), the hook's stderr directs the user to open this project
in Claude Code and run `/gitlore:resolve`. The primary path resumes from there.

**Clone**

`git clone --recurse-submodules <repo>` → the first `SessionStart` configures
settings, detaches memory at `live`, and replays the hook-manager sentinel.

Without `--recurse-submodules`: `SessionStart` detects the uninitialized
submodule and runs `git submodule update --init`. That leaves the memory
submodule at a **detached HEAD** on the recorded gitlink SHA with only the
remote-tracking `origin/live` — no local branches. Since the branch-model logic
references `live` as a *local* ref (checkout source and ff-merge target),
`SessionStart` first materializes a local `live` from `origin/live` (falling
back to the checked-out `HEAD` when memory has no remote), then proceeds as
above. Without it the first post-clone session dies on
`fatal: 'live' is not a commit`.

**Worktree creation** — `SessionStart` in the new worktree initializes the
memory submodule worktree, detached at `live`. Uniform across
`claude --worktree`, manual `git worktree add`, and the Desktop button (all
start a session in the worktree). Why no `WorktreeCreate` hook is registered is
in [session.md](session.md).
