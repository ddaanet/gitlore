# Components

The detail behind the Components map in `design.md`: what each command, skill,
hook and entry point does, and which decision and node argues it. Read it while
changing or invoking one of them. `design.md` keeps the map; the conclusions are
in [decisions.md](../decisions.md).

The components divide by who invokes them: the user or the agent reach the
commands and skills, git fires the one git hook, Claude Code fires the rest, and
the two entry points are callable by any of them. What they share is the
NFR1/NFR4 split — the agent writes prose or an intent on stdin, a script does
the git and decides (D7).

- **Commands** — `/gitlore:install`, one-time idempotent setup that runs from
  the **main worktree** only and leaves the remote, submodule, settings keys,
  launcher and hook wiring staged for the user to commit
  ([installation.md](installation.md)); and `/gitlore:add-tier`, which mounts an
  existing shared tier or creates a new one by calling `gitlore-add-tier`
  directly, the intent as `key=value` lines on stdin through a quoted heredoc;
  into a memory store with no unapproved work, the mount commits itself under a
  canned message (D32, D71, in [tiered-memory.md](tiered-memory.md)); and
  `/gitlore:index-audit`, the store-wide curation pass, a command because a
  human decides to run it (D47, in
  [memory-authoring-guidance.md](memory-authoring-guidance.md)).
- **Skills** — `resolve`, the semantic merge of a diverged store, split across a
  gate, a fresh-context sub-agent (D9), the parent's approval and a continuation
  script; `commit`, which carries the summary format and the commit protocol,
  the approved summary passed to `gitlore-commit` (D19, D70); `push`, which
  publishes every store with no parent push and no approval step, because FR11
  gated the content at commit time; `merge`, which takes what every remote
  holds, repairing an arriving index the root cannot adopt, and publishes
  nothing (D43, D49, D52); `recall`, which fetches bodies into context mid-task
  with no hook, no request file and no state (D18); and `memory-writing`,
  whether a learning becomes a fact, what it says, which tier it lands in,
  whether its line routes, which sibling project owns it per the owned-projects
  inventory, and where it is invoked (D47, D48, D69). Each is a skill rather
  than a command because each has an entry no user types — a hook's stderr, a
  session start, an ending session, a token in a tool result, a write under
  `memory/`. Steps in [merge-and-resolve.md](merge-and-resolve.md). A divergence
  is published, not carried: `push` publishes each store as soon as it is ready
  (D75), and a position report hints `push` for any divergence and `merge` only
  for a fast-forward take (D76), because an unpublished merge is redone at every
  upstream update ([publishing-divergence.md](publishing-divergence.md)).
- **Claude Code hooks** — `SessionStart` reports and writes no index and moves
  no module (D59, D74), and does the most work; it is also where a new
  worktree's memory worktree is created, lazily, so worktree support is uniform
  however the worktree came to be (no `WorktreeCreate` hook; `WorktreeRemove`
  tears it down, advisory only). The rest are single-purpose: `PostToolBatch`
  reports a mid-session plugin upgrade (D21), the `PreToolUse`/`PostToolBatch`
  index pair keys on what changed rather than on what the call declared (D31),
  per agent so a parent batch cannot consume a subagent's baseline, a
  `PostToolBatch` relay drainer delivers — as `SessionStart` does at a
  compaction or resume — the reports hooks write from inside a subagent, whose
  own output reaches nobody else (D51), and
  `PostToolUse(EnterWorktree|ExitWorktree)` guards against in-process worktree
  drift (D15); `SessionStart(startup|clear|compact)` re-arms the
  once-per-episode notices. Each `PostToolBatch` hook calls one shared guard
  that turns its death into a report on both channels with exit 0, since exit 2
  there ends the turn and exit 1 tells the agent nothing (D60, in
  [cc-platform.md](cc-platform.md)). [session.md](session.md),
  [hook-wrappers.md](hook-wrappers.md),
  [plugin-upgrade-notice.md](plugin-upgrade-notice.md); the index pair in
  [index-composition.md](index-composition.md) (the edit that removes a stale
  pointer line, D66, in [index-drift-fixes.md](index-drift-fixes.md)), the
  per-agent keying and the relay in
  [index-authoring-sync.md](index-authoring-sync.md), D51 in
  [cc-platform.md](cc-platform.md).
- **Git hook and entry points** — `pre-push` publishes each tier's `live` and
  then memory's; it stands down rather than block a parent git operation over an
  absent store, and divergence prepares a merge and yields to
  `/gitlore:resolve`. A parent commit touches no memory: `commit-memory.sh`, run
  as `gitlore-commit`, is the one commit path (D70). It takes the summary on
  stdin, writes no index and aborts when a compose pass would change one
  (`gitlore-compose` is the remedy), and aborts on a compose problem in an index
  file the commit changes, which committing would publish (D50); it commits
  every dirty tier, then memory, advances each store's local `live`, and stages
  the memory gitlink into the parent index, so the next parent commit records
  the pointer with no hook (D58, in
  [memory-commit-ownership.md](memory-commit-ownership.md)). `push-memory.sh`
  does the publish work as a callable script, both scripts reached by the plugin
  `bin/` names `gitlore-commit` and `gitlore-push` (D16, D20, D70); sharing a
  body with the hook keeps the tier-before-memory ordering from drifting between
  the two paths (D42). The hook ordering and the gitlink contract are in
  [git-hooks.md](git-hooks.md); the two scripts, the `push` skill and the
  placeholder-remote marker are in
  [memory-entry-points.md](memory-entry-points.md).
