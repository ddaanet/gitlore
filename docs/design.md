# gitlore Design Document

gitlore is a Claude Code plugin that makes Claude's auto-memory versioned,
shared and git-backed. Memory lives in a git submodule inside the project repo,
every memory commit passes a user-approved review gate, and portable facts are
shared across repos through nested *tier* submodules.

This is the living design: what the system does, how it is built, and why it is
built that way. It is kept in the present tense, and git history is its
changelog
([design-history.md](references/design-history.md)).
[decisions.md](decisions.md) is the decisions index: one conclusion line per
decision and every rejected alternative by name. `docs/references/` is a graph
of nodes, one per mechanism, each holding the detail behind a section here and
the decisions and rejected alternatives arguing for it. The sections here
summarize; read the node before making a claim about the mechanism it argues.
Plans and specs live in `plans/`.

**Created:** 2026-04-11

---

## Functional Requirements

1. Memory files are versioned in git, inside the project repo, as a submodule.
2. Memory is shared across Claude Code sessions on the same project.
3. Every worktree shares one memory trunk (`live`); each checkout sits detached
   at it, so concurrent worktrees never compete for a branch.
4. On the happy path, the agent drives memory commits: it summarizes pending
   memory changes in prose, obtains explicit user confirmation, then commits
   through `gitlore-commit` with the approved summary on stdin, one section per
   store — approving the summary approves the commit *(D70)*. A parent commit
   never commits memory; it records the pointer that script staged *(D58)*.
5. When any divergence is detected (pending commit vs. trunk, or local trunk vs.
   remote), `/gitlore:resolve` performs a semantic merge: a sub-agent with fresh
   context synthesizes the merged content, reviewed by the parent agent — never
   the user *(D49)* — before the merge lands under a canned message.
6. One-command install configures the entire system.
7. After `git clone`, the first `SessionStart` restores working state
   automatically. Running `/gitlore:install` again is not required; the plugin's
   own install is the only prerequisite.
8. Memory is pushed to a dedicated remote repository with double-commit
   semantics — memory `live` is pushed before the parent push on every
   `git push`. It is also publishable on its own, with no parent push and no
   `git` command typed by hand *(D20)*.
9. Remote creation is provider-agnostic; `gh` CLI is used opportunistically when
   available.
10. **Install-time disclosure (informational).** Before creating the memory
    remote, the user is shown the proposed name, owner, visibility, and a notice
    that memory may contain session context — orientation, not a hard gate.
11. **Per-commit review gate.** Every memory commit *authoring* content requires
    explicit user approval of a prose summary before the commit executes — the
    effective control over what reaches the remote. Merge and take-bookkeeping
    commits are its stated exemption: both sides already passed this gate
    *(D49)*. So is a take's repair of an arriving index, which restructures
    lines upstream already approved and adds no text *(D52)*. So is the commit
    `/gitlore:add-tier` makes to record a mount or a create in a store with no
    unapproved work, whose content follows from the user's request *(D71)*.
12. **Coexistence.** Repos without a memory submodule are unaffected when the
    plugin is present; every hook no-ops silently when it is not registered.
13. **Recovery.** If memory enters a broken state (missing `live`, partial
    merge, locked checkout), tooling surfaces a clear error with recovery
    instructions rather than blocking parent git operations silently.
14. **Transparent per-project redirect.** Memory is redirected into the
    submodule without changing how the user invokes Claude Code — they keep
    typing `claude`, using CC's native auto-memory. The redirect is scoped to
    the project (no effect on other repos' memory) and applied at launch by the
    launcher.
15. **Tiered memory.** Portable facts (user-level, Claude Code platform
    `reference`, durable cross-project `feedback`) are shared across
    participating repos through one or more shared *tier* repos — an
    organization tier, a global tier — surfacing alongside the repo's own
    memory, while `project` facts stay repo-local. Tiers are additive and
    composed, never flattened into a single merged store. *(Mechanism in D17.)*
16. **Active recall.** A memory body can be fetched into context on demand,
    mid-task, from a trigger the user's prompt never carried — an error string
    in a tool result, a flag in a file just read. The agent selects from the
    index it already holds and reads the bodies itself, in one batch *(D18)*.

---

## Non-Functional Requirements

1. **No AI on the hot path.** The hook execution chain (pre-push) and the commit
   and push scripts run entirely in shell; the agent is invoked out-of-band for
   commit-summary preparation, conflict resolution, and user interaction.
2. **Noisy failure with actionable instructions.** Hook failures exit 1 with a
   specific skill or command to run — never a generic error. Stderr branches on
   `$CLAUDECODE`: agent-facing text when the agent is present, user-facing text
   (directing them to open Claude Code) otherwise.
3. **Idempotent install.** `/gitlore:install` is safe to re-run after clone, on
   a new machine, or after a partial prior run.
4. **Scripts decide, agent handles language.** Detection and branching logic
   (hook manager, remote provider, merge state, divergence flavor) lives in
   shell scripts; the agent handles summarization, synthesis and user
   interaction.
5. **Double-commit semantics.** Memory is published before the parent push
   (`pre-push`), so the parent remote always points to a memory SHA reachable on
   the memory remote. The gitlink a parent commit records is an ancestor of
   memory's `live`, and floats behind it between commits.
6. **No tracked-file churn on plugin updates.** Hook scripts live in the plugin
   cache, not in the repo. Only stable wiring (hook manager config, sentinel
   file, `.claude/settings.json` flag) is committed.
7. **Works with common git hook managers.** Husky, Lefthook, Overcommit, or
   plain `.git/hooks/`. Unknown managers fall back to a copy-paste snippet.
8. **Graceful degradation.** If memory is in a broken state, guard clauses
   (`.gitmodules` check, memory submodule init check, hooks-installed check)
   keep parent git operations unblocked.
9. **Two test tiers, split by what each can see.** The bats suites own the edge
   cases and every script's contract; the eval harness owns the **happy paths**,
   driven through the real agent, because the seam between the agent and the
   shell is invisible to bats. The split and the `pass^k` shape are in
   [testing.md](references/testing.md).
10. **The gate is cheap enough to run on every commit.** Not met for a full run,
    which is barely parallel — cutting per-case work is the lever, not `--jobs`.
    The cost is narrowed in two steps rather than one. Four per-recipe gates
    (`lint`, `test-unit`, `test-integration`, `check-distribution`) skip
    outright when their declared inputs are unchanged; beneath them two
    sub-caches — per shell file in `tools/lint-shell.sh`, per suite in
    `tools/run-bats-cached.sh` — narrow a run that does happen to what the
    change reaches, so an edit to one suite or one script costs a fraction of
    the pass. An edit under `scripts/`, `hooks/` or `tests/helpers/` still pays
    the full one, and no full-run measurement postdating the sub-caches is
    recorded. Measurement in [testing.md](references/testing.md).
11. **Overrides.** Confirmation gates described here are defaults; project or
    user instructions (`CLAUDE.md` and equivalents) can relax them, so a user
    who wants auto-commit or auto-push can document the override.
12. **Bounded artifacts.** Every artifact a reader takes in at one go stays
    under 20000 bytes (10000 for a `SKILL.md` hub) — a `docs/` node, a script, a
    hook, a bats suite alike — because the cap rations a context window rather
    than tidying documentation, and the toolkit's `check-size` blocks past it
    (D73). What the count stands in for, the need-time seam a split follows, and
    why the rule outside `docs/` needed a gate are in
    [artifact size](references/artifact-size.md).

---

## Architecture

### Memory Submodule

Memory lives at a configurable path inside the project repo, chosen at install
time (default `memory/`, common alternative `.claude/memory/`). The submodule is
always named `gitlore-memory` in `.gitmodules` regardless of its working-tree
path, so `git config --file .gitmodules submodule.gitlore-memory.path` is the
canonical source of truth for the path and no duplicate local config key is
maintained.

### Branch Model

Every gitlore store — the memory submodule and each tier nested inside it — uses
the same model: **`live` is the sole persistent, travelling ref, and the working
tree is checked out detached at `live`'s commit.** No store ever has a named
working branch, so nothing tracks the parent repo's branch names, and git's
one-branch-per-worktree rule never binds — which it would on the memory store,
whose worktrees share one gitdir. A tier is the opposite: each memory worktree
clones it separately, so a named branch would diverge rather than collide.

The gitlink a parent commit records is always an ancestor of memory's `live`, or
`live` itself. A gitlink behind memory's tip is the resting state, recorded by
the next parent commit, so a push refused by divergence is resolved and pushed
again, and no parent commit is ever rewritten to re-pin memory (D46).

The session-start report, the advance after a commit, the two divergence gates
that reduce to one shape (D6, D41), and why the parent's ref layout is no
concern of memory's are in [branch-model.md](references/branch-model.md); the
gitlink invariant is in
[git-hooks.md](references/git-hooks.md).

A store whose remote history was rewritten publishes a rewrite record beside
`live`, and a clone still on the old history is refused at the divergence gate
rather than merged back (D61, D62), and a damaged record is rebuilt from scratch
from the commit-maps at hand (D63); the record, the detection, the manual
crossing and the rebuild are in
[history-rewrites.md](references/history-rewrites.md).

### Configuration

Configuration splits three ways by what has to travel. Tracked state — the
activation flag, the launcher shim and `.envrc`, the hook-manager sentinel, the
tier manifest (D30) — travels with the repo. The one git-config key,
`gitlore.hooksDir`, is per-clone and machine-local, points at the installed
plugin, and is re-pinned every `SessionStart`, which is what makes it
self-healing (D5). No IPC file remains: the add-tier intent, like the commit
summary, travels as stdin to a `bin/` entry point (D70, D71). Every file and key
is in [configuration.md](references/configuration.md).

### Memory Redirect Launcher

Claude Code's native auto-memory writes to
`~/.claude/projects/<sanitized-cwd>/memory/` unless `autoMemoryDirectory` is set
in an honored settings tier. Project settings honor only an absolute value,
fixed at launch, so the redirect is injected at launch through the `--settings`
flag by a thin `claude` shim (D10) — the user keeps typing `claude`, and memory
lands in the submodule. The shim redirects only to the memory submodule's own
path and launches unredirected, with one stderr line saying why, when
`.gitmodules` names anything else (D68). Shim body, its two placements and the
`GITLORE_LAUNCHED` sentinel that stops them double-injecting:
[memory-redirect.md](references/memory-redirect.md).

### Components

The components divide by who invokes them: the user or the agent reach the
commands and skills, git fires the one git hook, Claude Code fires the rest, and
the two entry points are callable by any of them. What they share is the
NFR1/NFR4 split — the agent writes prose or an intent on stdin, a script does
the git and decides (D7).

- **Commands** — `/gitlore:install`, one-time idempotent setup that runs from
  the **main worktree** only and leaves the remote, submodule, settings keys,
  launcher and hook wiring staged for the user to commit
  ([installation.md](references/installation.md)); and `/gitlore:add-tier`,
  which mounts an existing shared tier or creates a new one by calling
  `gitlore-add-tier` directly, the intent as `key=value` lines on stdin through
  a quoted heredoc; into a memory store with no unapproved work, the mount
  commits itself under a canned message (D32, D71, in
  [tiered-memory.md](references/tiered-memory.md)); and `/gitlore:index-audit`,
  the store-wide curation pass, a command because a human decides to run it
  (D47, in
  [memory-authoring-guidance.md](references/memory-authoring-guidance.md)).
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
  `memory/`. Steps in [merge-and-resolve.md](references/merge-and-resolve.md). A
  divergence is published, not carried: `push` publishes each store as soon as
  it is ready (D75), and a position report hints `push` for any divergence and
  `merge` only for a fast-forward take (D76), because an unpublished merge is
  redone at every upstream update
  ([publishing-divergence.md](references/publishing-divergence.md)).
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
  [cc-platform.md](references/cc-platform.md)).
  [session.md](references/session.md),
  [hook-wrappers.md](references/hook-wrappers.md),
  [plugin-upgrade-notice.md](references/plugin-upgrade-notice.md); the index
  pair in [index-composition.md](references/index-composition.md) (the edit that
  removes a stale pointer line, D66, in
  [index-drift-fixes.md](references/index-drift-fixes.md)), the per-agent keying
  and the relay in
  [index-authoring-sync.md](references/index-authoring-sync.md), D51 in
  [cc-platform.md](references/cc-platform.md).
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
  [memory-commit-ownership.md](references/memory-commit-ownership.md)).
  `push-memory.sh` does the publish work as a callable script, both scripts
  reached by the plugin `bin/` names `gitlore-commit` and `gitlore-push` (D16,
  D20, D70); sharing a body with the hook keeps the tier-before-memory ordering
  from drifting between the two paths (D42). The hook ordering and the gitlink
  contract are in [git-hooks.md](references/git-hooks.md); the two scripts, the
  `push` skill and the placeholder-remote marker are in
  [memory-entry-points.md](references/memory-entry-points.md).

### Install-time surfaces

Hook-manager wiring and memory-remote creation are install-time concerns, read
when changing `/gitlore:install` rather than when reasoning about memory itself.
Wiring detects Lefthook, Husky, Overcommit or nothing, defaults to `direct` so
FR8 holds out of the box, and reaches the wrapper through the git common dir
(D11); `SessionStart` replays only the three commands the wire scripts write
(D45). The remote inherits name, owner and visibility from the parent's
`origin`, is disclosed before creation (FR10), and a parent with no remote is a
supported local-only end state. The detection table and each manager's syntax
are in [installation.md](references/installation.md); the disclosure text and
the per-provider creation methods are in
[memory-remote.md](references/memory-remote.md).

### Workflows

The step lists are in [workflows.md](references/workflows.md): commit (prose
summary, approval, `gitlore-commit`, then the parent commit); push (`pre-push`,
tiers then memory); tier write (rides the commit flow, tier first, under one
summary); publish without a parent push (`/gitlore:push` over `gitlore-push`);
take without publishing (`/gitlore:merge`, tiers first and root last, D49, D77);
resolve, primary when the agent reads a gate's stderr and resolves inline,
fallback when a plain terminal sends the user to Claude Code; clone (the first
`SessionStart` restores settings, `live` and wiring); worktree creation
(`SessionStart` adds the memory worktree, detached).

---

## Design Decisions

Every conclusion, grouped by the node that argues it, with the rejected
alternatives named under each group, is in [decisions.md](decisions.md). That
file is the one to read whole before weighing a new decision; the argument is
one hop further, in the node.

---

## Rejected Alternatives

Named on the *Rejected* line of each decision group in
[decisions.md](decisions.md) and argued in the `## Rejected alternatives`
section that closes the group's node. A decision that is later inverted or
retired is deleted from the index and its node, with its why in the deleting
commit (D72, [design-history.md](references/design-history.md)).
