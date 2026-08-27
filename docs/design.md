# gitlore Design Document

gitlore is a Claude Code plugin that makes Claude's auto-memory versioned,
shared and git-backed. Memory lives in a git submodule inside the project repo,
every memory commit passes a user-approved review gate, and portable facts are
shared across repos through nested *tier* submodules.

This is the living design: what the system does, how it is built, and why it is
built that way. It is kept in the present tense — how it got here is in
[changelog.md](changelog.md). `docs/references/` is a graph of nodes, one per
mechanism, each holding the detail behind a section here and the decisions and
rejected alternatives arguing for it. The sections here summarize; read the
node before making a claim about the mechanism it argues. Plans and specs live
in `plans/`.

**Created:** 2026-04-11

---

## Functional Requirements

1. Memory files are versioned in git, inside the project repo, as a submodule.
2. Memory is shared across Claude Code sessions on the same project.
3. Every worktree shares one memory trunk (`live`); each checkout sits detached
   at it, so concurrent worktrees never compete for a branch.
4. On the happy path, the agent drives memory commits: it runs the configured
   pre-commit command, summarizes pending memory changes in prose, obtains
   explicit user confirmation, writes the approved summary as the commit
   message, then commits — approving the summary approves the commit.
5. When any divergence is detected (local branch vs. trunk, or local trunk vs.
   remote), `/gitlore:resolve` performs a semantic merge: a sub-agent with fresh
   context synthesizes the merged content, and the parent agent approves the
   summary with the user before the merge is committed.
6. One-command install configures the entire system.
7. After `git clone`, the first `SessionStart` restores working state
   automatically. Running `/gitlore:install` again is not required; the plugin's
   own install is the only prerequisite.
8. Memory is pushed to a dedicated remote repository with double-commit
   semantics — memory `live` is pushed before the parent push on every
   `git push`. It is also publishable on its own, with no parent push and no
   `git` command typed by hand. *(Mechanism in D20.)*
9. Remote creation is provider-agnostic; `gh` CLI is used opportunistically when
   available.
10. **Install-time disclosure (informational).** Before creating the memory
    remote, the user is shown the proposed name, owner, visibility, and a notice
    that memory may contain session context — orientation, not a hard gate.
11. **Per-commit review gate.** Every memory commit (including merge commits
    produced by `/gitlore:resolve`) requires explicit user approval of a prose
    summary before the commit message file is written and the commit executes.
    This is the effective control over what reaches the remote.
12. **Coexistence.** Repos without a `gitlore-memory` submodule are unaffected
    when the plugin is present; every hook no-ops silently when it is not
    registered.
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
    index it already holds and reads the bodies itself, in one batch.
    *(D18.)*

---

## Non-Functional Requirements

1. **No AI on the hot path.** The hook execution chain (pre-commit, pre-push)
   runs entirely in shell scripts; the agent is invoked out-of-band for
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
5. **Double-commit semantics.** Memory is committed and pushed before the
   parent commit/push, so the parent remote always points to a memory SHA
   reachable on the memory remote.
6. **No tracked-file churn on plugin updates.** Hook scripts live in the plugin
   cache, not in the repo. Only stable wiring (hook manager config, sentinel
   file, `.claude/settings.json` flag) is committed.
7. **Works with common git hook managers.** Husky, Lefthook, Overcommit, or
   plain `.git/hooks/`. Unknown managers fall back to a copy-paste snippet.
8. **Graceful degradation.** If memory is in a broken state, guard clauses
   (`.gitmodules` check, memory submodule init check, hooks-installed check)
   keep parent git operations unblocked.
9. **Two test tiers, split by what each can see.** The bats suites
   (`tests/*.bats`) own the edge cases and every script's contract, called the
   way production calls it. The eval harness (`tests/evals/`) owns the
   **happy paths**, driven through the real agent, because the seam between the
   agent and the shell is invisible to bats: no assertion can drive "a session
   starts, the agent edits memory, the user approves, the commit lands," and a
   prompt has no assertion-level test at all. Scenarios stay in the `pass^k`
   shape the harness already uses, so an agent-side flake stays distinguishable
   from a regression. Edge cases do not go in an eval; an eval's value is
   proving the whole chain fits together.
10. **The gate is cheap enough to run on every commit.** Not currently met.
    `just precommit` — `format-docs`, `check-distribution`, then
    `check-version lint test` — runs 530 s over 620 cases (measured 2026-07-29
    on the 2-vCPU dev droplet, `--jobs 2`; `check-distribution` adds ~2 s and
    carries its own sentinel, so a change confined to `agents/`, `commands/` or
    `skills/` pays only that). `user + sys` came to 566 s against 530 s wall, so
    the suite is barely parallel and more cores would not divide the number.
    Making it faster is open work, and cutting per-case work is the lever, not
    raising `--jobs`. `bats -T` reports per-test timings, so the breakdown that
    would direct that work comes free on the next full run. The input-hash
    sentinel caches a green result, so the full cost is paid precisely when a
    change is in flight.
11. **Overrides.** Confirmation gates described here are defaults; project or
    user instructions (`CLAUDE.md` and equivalents) can relax them, so a user
    who wants auto-commit or auto-push can document the override.

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
one-branch-per-worktree rule never binds. That last point is load-bearing for
tiers, whose gitdir is shared across all of a repo's memory worktrees: named
branches there would collide.

The session-start detach and fast-forward, the advance after a commit, the two
divergence gates that reduce to one shape (D6, D41), and why the parent's ref
layout is no concern of memory's are in
[merge-and-resolve.md](references/merge-and-resolve.md).

### Configuration

Configuration splits three ways by what has to travel. Tracked state — the
activation flag, the launcher shim and `.envrc`, the hook-manager sentinel, the
tier manifest (D30) — travels with the repo. The five git-config keys are
per-clone and machine-local, point at the installed plugin, and are re-pinned
every `SessionStart`, which is what makes them self-healing (D5). The IPC files
are transient handshakes between the agent and the hooks, and sit in the parent
working tree rather than a gitdir because a gitdir write is blocked by the CC
sandbox and read as self-configuration by the auto-mode classifier. Every file
and key is in
[configuration.md](references/configuration.md).

### Memory Redirect Launcher

Claude Code's native auto-memory writes to
`~/.claude/projects/<sanitized-cwd>/memory/` unless `autoMemoryDirectory` is set
in an honored settings tier. Project settings are *not* honored (D10), so the
only per-project, non-global mechanism is the `--settings` flag at launch,
injected by a thin `claude` shim — the user keeps typing `claude`, and memory
lands in the submodule. Shim body, its two placements, the `GITLORE_LAUNCHED`
sentinel that stops them double-injecting, and the
`GITLORE_AUTO_CLAUDE_PLUGIN_DIR` opt-in:
[memory-redirect.md](references/memory-redirect.md).

### Components

The components divide by who invokes them: the user or the agent reach the
commands and skills, git fires the two git hooks, Claude Code fires the rest,
and the two entry points are callable by any of them. What they share is the
NFR1/NFR4 split — the agent writes prose or an intent file, a script does the
git and decides (D7).

- **Commands** — `/gitlore:install`, one-time idempotent setup that runs from
  the **main worktree** only and leaves the remote, submodule, settings keys,
  launcher and hook wiring staged for the user to commit
  ([installation.md](references/installation.md)); and `/gitlore:add-tier`,
  which mounts an existing shared tier or creates a new one by writing an intent
  file a `PostToolBatch` hook acts on, because the agent can do neither half
  itself (D32, in [tiered-memory.md](references/tiered-memory.md)).
- **Skills** — `resolve`, the semantic merge of a diverged store, split across a
  gate, a fresh-context sub-agent (D9), the parent's approval and a continuation
  script; `push`, which publishes every store with no parent push and no
  approval step, because FR11 gated the content at commit time; `merge`, which
  takes what every remote holds and publishes nothing, and is the only path by
  which a pinned tier advances (D43); and `recall`, which fetches bodies into
  context mid-task with no hook, no request file and no state (D18). Each is a
  skill rather than a command because each has an entry no user types — a hook's
  stderr, a session start, an ending session, a token in a tool result. Steps in
  [merge-and-resolve.md](references/merge-and-resolve.md).
- **Claude Code hooks** — `SessionStart` is the self-healing pass and does the
  most work; it is also where a new worktree's memory worktree is created,
  lazily, so worktree support is uniform however the worktree came to be (no
  `WorktreeCreate` hook; `WorktreeRemove` tears it down, advisory only). The
  rest are single-purpose:
  `PostToolUse(Bash)` nudges for a commit summary once per dirty episode (the
  FR11 opening), `PostToolBatch` acts on the two intent files and reports a
  mid-session plugin upgrade (D21), the `PreToolUse`/`PostToolBatch` index pair
  keys on what changed rather than on what the call declared (D31), and
  `PostToolUse(EnterWorktree|ExitWorktree)` guards against in-process worktree
  drift (D15); `SessionStart` and `PreCompact` re-arm the once-per-episode
  notices. [session.md](references/session.md); the nudge in
  [commit-gate.md](references/commit-gate.md), the index pair in
  [index-composition.md](references/index-composition.md).
- **Git hooks and entry points** — `pre-commit` commits every dirty tier, then
  memory, advances each store's local `live`, and stages the memory gitlink into
  the index git handed it, so the parent commit records the pointer its own hook
  just created; `pre-push` publishes in the same order. Both stand down rather
  than block a parent git operation, and divergence at either gate prepares a
  merge and yields to `/gitlore:resolve`. `commit-memory.sh` and
  `push-memory.sh` do the same work as callable scripts discovered through a
  git-config key (D5, D16, D20); sharing a body with the hook keeps the
  tier-before-memory ordering from drifting between the two paths (D42).
  Orderings, contracts and the placeholder-remote marker are in
  [git-hooks-and-entry-points.md](references/git-hooks-and-entry-points.md).

### Hook Manager Support

The wrappers have to run whether the project drives git hooks through Lefthook,
Husky, Overcommit, or nothing at all. Detection picks one by first match, wiring
is idempotent behind a `# gitlore: managed` marker, and the sentinel stores the
command so `SessionStart` can replay it. `direct` is the default whenever no
manager is recognized — every git repo has a hooks dir, so FR8's double-commit
guarantee is active out of the box — and `manual` prints a snippet and modifies
nothing. The replay matches the sentinel against the three manager commands the
wire scripts write and runs nothing else (D45). The detection table, each
manager's wiring syntax, and why all of them reach the wrapper through
`$(git rev-parse --git-common-dir)/gitlore-<hook>` rather than a literal path
(D11) are in
[installation.md](references/installation.md).

### Workflows

The step lists are in [workflows.md](references/workflows.md): commit (nudge,
prose summary, approval, `pre-commit`); push (`pre-push`, tiers then memory);
tier write (rides the commit flow, tier first, under one summary); publish
without a parent push (`/gitlore:push` over `push-memory.sh`); resolve, primary
when the agent reads a gate's stderr and resolves inline, fallback when a plain
terminal sends the user to Claude Code; clone (the first `SessionStart` restores
settings, `live` and wiring); worktree creation (`SessionStart` adds the memory
worktree, detached).

### Remote Repository

The memory submodule is pushed to a dedicated remote of its own. Every default
is inherited from the parent's `origin` — name (`<parent-remote-name>-memory`),
owner, and visibility — and each is overridable at creation time. A parent with
no remote gets no memory remote and memory stays local-only, a supported end
state rather than a half-finished install. Creation is disclosed before it
happens (FR10), as orientation rather than a clearance gate — the effective gate
is the per-commit review (FR11); NFR5 orders the pushes. The rules in full, the
disclosure text and the per-provider creation methods are in
[installation.md](references/installation.md).

---

## Design Decisions

Grouped by the node that argues them: the conclusion is here, the argument —
what was weighed, what was rejected, and why — is one hop away.

**Merge and resolve** — the branch model and the divergence path.
[merge-and-resolve.md](references/merge-and-resolve.md)

- **D1** — `live` is the memory trunk, decoupled from the parent's default
  branch
- **D2** — superseded by D41's detached-at-`live` model; kept for the record
- **D3** — ordinary checkout during resolve, not git plumbing
- **D6** — merge direction: the more-authoritative side is the first parent
- **D7** — scripts decide, the agent handles language
- **D9** — a sub-agent synthesizes the merge (requires the experimental flag)
- **D13** — a lock-contention retry wrapper guards mutating memory git calls
- **D24** — a directive that names a sub-agent carries its own authorization
- **D41** — detached at `live`: one branch model, one commit path, every store

*Rejected:* `live` as a working branch · `git commit-tree` plus `git update-ref`
for the resolve merge · a temporary worktree for resolve · `claude --print` for
conflict resolution · single-agent resolve with a post-hoc context refresh.

**The commit gate** — FR11's approval machinery.
[commit-gate.md](references/commit-gate.md)

- **D4** — commit message by file handshake; its presence is the approval signal
- **D12** — a submodule-side commit gate backs FR11 as defense in depth
- **D19** — one canonical approval clause, discovered via a git-config key
- **D22** — the memory-hygiene checker is a repo-local gate, not shipped surface

*Rejected:* a `Stop` hook to generate the commit message · `PostToolUse` on
every memory `Write`/`Edit` · an interactive prompt inside the `pre-commit` hook
· an in-session diff dump for commit review · a `PreToolUse` hook constraining
the agent's git operations.

**Git hooks and entry points** — satisfying FR11 and FR8 with no parent commit
or push in flight.
[git-hooks-and-entry-points.md](references/git-hooks-and-entry-points.md)

- **D16** — a standalone, arg-driven memory-commit entry point
- **D20** — a push entry point the skill calls directly, with no trigger file

*Rejected:* triggering a memory commit through a parent commit · reimplementing
the sentinel, `push HEAD:live` and merge-state logic in a caller · a caller that
pre-writes the commit-message file.

**Install and the memory remote** — what one-time setup does and refuses.
[installation.md](references/installation.md)

- **D8** — remote creation requires explicit user confirmation
- **D25** — direct wiring refuses rather than appends after an existing `exec`
- **D45** — the sentinel replay is an allow-list, never `sh -c` on the tracked
  file

*Rejected:* a strictly non-empty initial commit · `gh repo create` as the only
remote-creation method · a separate `gitlore.memoryPath` config key · making the
memory push optional in v1 · replaying the sentinel as a shell command.

**Memory redirect** — [memory-redirect.md](references/memory-redirect.md)

- **D10** — the redirect is a launch-time `--settings` shim, not a project
  setting

*Rejected:* `autoMemoryDirectory` in project settings · the same key in global
`~/.claude/settings.json` · `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` via `.envrc` ·
an explicit `gitlore` launch command instead of shadowing `claude`.

**The session and its wrappers** — where the wrappers live and are anchored,
and what SessionStart says to whom.
[session.md](references/session.md)

- **D5** — wrapper scripts live in the git common dir, untracked
- **D11** — wrapper paths anchor at the git common dir, so linked worktrees work
- **D14** — user-facing SessionStart output goes on `systemMessage`
- **D21** — a mid-session plugin upgrade is a notice, not a self-healing config

*Rejected:* tracked hook scripts in the repo · a literal `.git/gitlore-<hook>`
wrapper path · a per-worktree wrapper anchor · a `WorktreeCreate` hook · a
version-less plugin pointer resolved at hook runtime · wrappers self-healing
from `CLAUDE_PLUGIN_ROOT`.

**Claude Code platform workarounds** — harness behaviours, each carrying the
empirical work that established it, which is why they stay whole.
[cc-platform.md](references/cc-platform.md)

- **D15** — an in-process-worktree memory-drift guard
- **D18** — active recall is a skill the agent runs itself: no hook, no state
- **D23** — the `Edit` weld defect is contained by a pair that computes the
  intended result, repairs, and reports its own obsolescence

*Rejected:* hook-side injection of the bodies from a request file the agent
writes · a `PreToolUse` deny on the first durable write of an episode.

**Tiered memory** — D17 is the call; the subsystem's own decisions conclude in
the opening summary of each node: retrieval and routing (D26–D28, D32, D33) in
[tiered-memory.md](references/tiered-memory.md), composition (D29–D31,
D34–D37) in [index-composition.md](references/index-composition.md), the
authoring-time sync (D38–D40) in
[index-authoring-sync.md](references/index-authoring-sync.md), and the tier
stores and merges (D42–D44) in [tier-stores.md](references/tier-stores.md).

- **D17** — FR15: nested tier submodules plus a structurally composed root index

*Rejected:* a flat merge-everything store · a content classifier routing each
new fact (tiered-memory.md) · propagating the root index down into the carriers
· recompose owning index-line presence · deleting a memory file when its pointer
line is removed · a `SessionStart` warning when a tier is mounted without a
paired guard plugin (index-composition.md) · frontmatter `description` as the
source of truth for the index one-liner · scoring an index hook against its
body, tf-idf style (index-authoring-sync.md) · an append-only constraint on
shared-tier indexes · a `merge` driver plus `.gitattributes` ·
`**/MEMORY.md merge=union` plus a dedup-by-path pass (tier-stores.md).

---

## Rejected Alternatives

Each is named on the *Rejected* line of its decision group above and argued in
the `## Rejected alternatives` section that closes that group's node. A
decision that was later inverted lives in the changelog, not here.

---

## Changelog

How the design got here is recorded in [changelog.md](changelog.md), newest
first.
