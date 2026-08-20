# gitlore Design Document

gitlore is a Claude Code plugin that makes Claude's auto-memory versioned, shared
and git-backed. Memory lives in a git submodule inside the project repo, every
memory commit passes a user-approved review gate, and portable facts are shared
across repos through nested *tier* submodules.

This is the living design: what the system does, how it is built, and why it is
built that way. It is kept in the present tense — how it got here is in
[changelog.md](changelog.md). Plans and specs live in `plans/` at the repo root,
reference material in `docs/references/`.

**Created:** 2026-04-11

---

## Functional Requirements

1. Memory files are versioned in git, inside the project repo, as a submodule.
2. Memory is shared across Claude Code sessions on the same project.
3. Every worktree shares one memory trunk (`live`); each checkout sits detached at it, so concurrent worktrees never compete for a branch.
4. On the happy path, the agent drives memory commits: runs the configured pre-commit command, summarizes pending memory changes in prose, obtains explicit user confirmation, writes the approved summary as the memory commit message, then commits. The user's approval of the summary doubles as approval of the commit itself.
5. When any divergence is detected (local branch vs. trunk, or local trunk vs. remote), `/gitlore:resolve` performs a semantic merge. A sub-agent with fresh context synthesizes the merged content; the parent agent approves the summary with the user before the merge is committed.
6. One-command install configures the entire system.
7. After `git clone`, the first `SessionStart` restores working state automatically. Running `/gitlore:install` again is not required; the plugin's own install is the only prerequisite.
8. Memory is pushed to a dedicated remote repository with double-commit semantics — memory `live` is pushed before the parent push on every `git push`. It is also publishable on its own, with no parent push and no `git` command typed by hand. *(Mechanism in D20.)*
9. Remote creation is provider-agnostic; `gh` CLI is used opportunistically when available.
10. **Install-time disclosure (informational).** Before creating the memory remote, the user is shown the proposed name, owner, visibility, and a notice that memory may contain session context. This is orientation, not a hard gate.
11. **Per-commit review gate.** Every memory commit (including merge commits produced by `/gitlore:resolve`) requires explicit user approval of a prose summary before the commit message file is written and the commit executes. This is the effective control over what reaches the remote.
12. **Coexistence.** Repos without a `gitlore-memory` submodule are unaffected when the plugin is present. All hooks no-op silently if the submodule is not registered.
13. **Recovery.** If memory enters a broken state (missing `live`, partial merge, locked checkout), tooling surfaces a clear error with recovery instructions rather than blocking parent git operations silently.
14. **Transparent per-project redirect.** Memory is redirected into the submodule without changing how the user invokes Claude Code — they keep typing `claude`, using CC's native auto-memory. The redirect is scoped to the project (no effect on other repos' memory) and applied at launch by the Memory Redirect Launcher.
15. **Tiered memory.** Portable facts (user-level, Claude Code platform `reference`, durable cross-project `feedback`) are shared across participating repos through one or more shared *tier* repos — e.g. an organization tier and a global tier — surfacing alongside the repo's own memory; `project` facts stay repo-local. Tiers are additive and composed, never flattened into a single merged store. *(Mechanism in D17.)*
16. **Active recall.** A memory body can be fetched into context on demand, mid-task, from a trigger the user's prompt never carried — an error string in a tool result, a flag in a file just read. The agent selects from the index it already holds and reads the bodies itself, in one batch. *(Mechanism in D18.)*

---

## Non-Functional Requirements

1. **No AI on the hot path.** The hook execution chain (pre-commit, pre-push) runs entirely in shell scripts. The agent is invoked out-of-band for commit-summary preparation, conflict resolution, and user interaction.
2. **Noisy failure with actionable instructions.** Hook failures exit 1 with a specific skill or command to run — never a generic error. Stderr branches on `$CLAUDECODE`: agent-facing text when the agent is present, user-facing text (directing them to open Claude Code) otherwise.
3. **Idempotent install.** `/gitlore:install` is safe to re-run after clone, on a new machine, or after a partial prior run.
4. **Scripts decide, agent handles language.** Detection and branching logic (hook manager, remote provider, merge state, divergence flavor) lives in shell scripts. The agent handles summarization, synthesis, and user interaction.
5. **Double-commit semantics.** Memory is committed and pushed before the parent commit/push. The parent remote always points to a memory SHA reachable on the memory remote.
6. **No tracked-file churn on plugin updates.** Hook scripts live in the plugin cache, not in the repo. Only stable wiring (hook manager config, sentinel file, `.claude/settings.json` flag) is committed.
7. **Works with common git hook managers.** Husky, Lefthook, Overcommit, or plain `.git/hooks/`. Unknown managers fall back to a copy-paste snippet.
8. **Graceful degradation.** If memory is in a broken state, guard clauses (`.gitmodules` check, memory submodule init check, hooks-installed check) keep parent git operations unblocked.
9. **Two test tiers, split by what each can see.** The bats suites (`tests/*.bats`) own the edge cases and every script's contract, called the way production calls it. The eval harness (`tests/evals/`) owns the **happy paths** — the ordinary flow a user walks, driven through the real agent — because the seam between the agent and the shell is invisible to bats: no assertion can drive "a session starts, the agent edits memory, the user approves, the commit lands," and a prompt has no assertion-level test at all. Scenarios stay in the `pass^k` shape the harness already uses, so an agent-side flake stays distinguishable from a regression. Edge cases do not go in an eval; an eval's value is proving the whole chain fits together.
10. **The gate is cheap enough to run on every commit.** Not currently met. `just precommit` — `check-distribution`, then `check-version lint test` — runs 530 s over 620 cases (measured 2026-07-29 on the 2-vCPU dev droplet, `--jobs 2`; `check-distribution` adds ~2 s and carries its own sentinel, so a change confined to `agents/`, `commands/` or `skills/` pays only that). `user + sys` came to 566 s against 530 s wall, so the suite is barely parallel and more cores would not divide the number; cutting per-case work is the lever, not raising `--jobs`. `bats -T` reports per-test timings, so the breakdown that would direct that work comes free on the next full run rather than needing a profiling pass of its own. The input-hash sentinel caches a green result, so the full cost is paid precisely when a change is in flight.
11. **Overrides.** Confirmation gates described here are defaults. Project or user instructions (`CLAUDE.md` and equivalents) can relax them — users who want auto-commit or auto-push can document the override.

---

## Architecture

### Memory Submodule

Memory lives at a configurable path inside the project repo (default: `memory/`, common alternative: `.claude/memory/`). Chosen at install time. The submodule is always named `gitlore-memory` in `.gitmodules` regardless of its working-tree path:

```sh
git config --file .gitmodules submodule.gitlore-memory.path   # → memory or .claude/memory
```

This is the canonical source of truth for the memory path; no duplicate local config key is maintained.

### Branch Model

Every gitlore store — the memory submodule and each tier nested inside it — uses the same model: **`live` is the sole persistent, travelling ref, and the working tree is checked out detached at `live`'s commit.** No store ever has a named working branch, so nothing tracks the parent repo's branch names, and git's one-branch-per-worktree rule never binds. That last point is load-bearing for tiers, whose gitdir is shared across all of a repo's memory worktrees: named branches there would collide.

- **Session start.** SessionStart detaches in place, then fast-forwards HEAD onto `live` when the store is clean. Uncommitted changes skip the fast-forward with a user-visible notice — memory is never moved out from under pending work. A store that arrives on a named branch (an install predating this model) is migrated by the same in-place detach.
- **After commit.** The commit path advances `live` immediately (`push . HEAD:live`, fast-forward only), so `live` holds every commit the moment it exists and memory is repo-global rather than branch-scoped. Divergence blocks and routes to `/gitlore:resolve`.
- **Two divergence gates, one shape.** A store's pending HEAD against its own local `live` (`pre-commit`), and its local `live` against its own `origin/live` (`pre-push`). Both reduce to "my pending commit vs the authoritative side", which is why one merge machinery serves memory and tiers alike (D6, D41).
- **Parent branch switches, rebases and force-pushes are independent of memory.** Memory history is its own concern; nothing in the parent's ref layout is mirrored.

### Configuration

Configuration splits three ways by what has to travel: tracked files travel with the repo, git-config keys are per-clone and machine-local, and the IPC files are transient handshakes between the agent and the hooks.

**Tracked — travels with the repo.** `.claude/settings.json` carries `gitlore.enabled: true` (the activation flag every hook guards on) and `gitlore.precommitCommand`, the project's own pre-commit check (e.g. `lefthook run pre-commit`) that the `PostToolUse` nudge watches for. `.gitlore/bin/claude` is the launcher shim and `.envrc` puts it on `PATH` (`source_up_if_exists` plus `PATH_add .gitlore/bin`) — see Memory Redirect Launcher. `.claude/gitlore-hook-setup` is the hook-manager sentinel — the setup command or keyword (`lefthook install`, `npx husky`, `overcommit --install`, `direct`, `manual`) that `SessionStart` replays to re-wire hook integration on a clone or a new machine. Inside the memory submodule, `memory/.gitlore-tiers` lists the active tiers in precedence order (D30).

**Local git config — never tracked, re-pinned every session.** Five keys point at the installed plugin, whose cache path changes on every upgrade: `gitlore.hooksDir` (the hook scripts the wrappers exec), `gitlore.commitCommand` (`commit-memory.sh`, D16), `gitlore.pushCommand` (`push-memory.sh`, D20), `gitlore.mergeCommand` (`merge-memory.sh`, D43) and `gitlore.memoryApprovalClauseFile` (the canonical approval wording, D19). All five are seeded at install and re-written by every `SessionStart`, which is what makes them self-healing; each consumer verifies the resolved path before using it rather than trusting the key (D5).

**IPC files — the agent writes, a hook acts.** `.claude/gitlore-memory-message` (the approved commit summary), `.claude/gitlore-commit-memory` (standalone-commit trigger) and `.claude/gitlore-add-tier` (mount intent) all sit in the parent working tree, gitignored. They live there rather than in a gitdir because a gitdir write is blocked by the CC sandbox and read as self-configuration by the auto-mode classifier — the agent can write an ordinary project file and nothing else. Hook-owned state that the agent must *not* write goes the other way, into the store's gitdir: the once-per-episode nudge marker `gitlore-nudged` and the merge-state file.

> **No `autoMemoryDirectory` in project settings.** Claude Code resolves `autoMemoryDirectory` only from `policySettings`, `flagSettings` (the `--settings` flag), or `userSettings` (`~/.claude/settings.json`) — never from project-level `.claude/settings.json` or `.claude/settings.local.json`, which it discards for security. The per-project redirect is therefore injected at launch by the Memory Redirect Launcher, not written to a settings file. See D10.

**Commit message file:** `.claude/gitlore-memory-message`, resolved by `gitlore_commit_msg_file` from the superproject working tree (`git -C <memory-path> rev-parse --show-superproject-working-tree`). Claude writes it once the user has confirmed the commit summary; the commit hook consumes and deletes it. Its presence is the signal that a memory commit carries approval (D4).

**Hook wrappers:** `SessionStart` writes `gitlore-pre-commit` and `gitlore-pre-push` into the repo's **git common dir** on every startup, and each delegates to the current plugin through `git config gitlore.hooksDir` — so hook-manager configs name a stable path and plugin updates are transparent. Resolving through `git rev-parse --git-common-dir` rather than a literal `.git/` is load-bearing (D11): the common dir is shared across worktrees, so one emission is reachable and executable from every worktree — including one where no Claude session has ever run — where `.git/` is a gitlink *file*. Every producer and every consumer resolves it that way; none hardcode it.

### Memory Redirect Launcher

Claude Code's native auto-memory writes to `~/.claude/projects/<sanitized-cwd>/memory/` unless `autoMemoryDirectory` is set in an honored settings tier. Project settings are *not* honored (D10), so the only per-project, non-global mechanism is the `--settings` flag at launch. The launcher is a thin `claude` shim that injects it transparently — the user keeps typing `claude`, and memory lands in the submodule. It ships in two placements over one identical body: repo-local under `.gitlore/bin/` with direnv putting it on `PATH` (the default, and both files travel with the repo), or a global shim at `~/.gitlore/bin/claude` when direnv is absent. A `GITLORE_LAUNCHED` sentinel makes the two compose rather than double-inject, and is also how `SessionStart` detects a plain `claude` launch and warns instead of silently stranding memory.

The shim body, the two placements' `PATH` mechanics, and the `GITLORE_AUTO_CLAUDE_PLUGIN_DIR` opt-in that loads the plugin from a local checkout are in [docs/references/installation.md](references/installation.md).

### Components

The components divide by who invokes them: the user or the agent reach the commands and skills, git fires the two git hooks, Claude Code fires the rest, and the two entry points are callable by any of them. What they share is the NFR1/NFR4 split — the agent writes prose or an intent file, a script does the git and decides (D7). What follows is what each component owns and what it talks to; the step lists and script contracts are in the reference files named alongside.

**Commands.** `/gitlore:install` is one-time setup, idempotent, and runs from the **main worktree** only — in a linked worktree the memory submodule is typically unchecked-out, so submodule git ops would silently escape to the parent repo and stage the parent's HEAD as the memory gitlink. It creates the remote, adds and seeds the submodule, writes the settings keys and the launcher, and wires the hook manager, leaving everything staged for the user to commit. `/gitlore:add-tier` mounts an existing shared tier or creates a new one; it writes an intent file and a `PostToolBatch` hook does the git, because mounting both mutates submodules and clones over the network, and the agent's sandbox and the auto-mode classifier each rule out one of those (D32). The install steps and their idempotency rules are in [docs/references/installation.md](references/installation.md); the mount's own machinery is in [docs/references/tiered-memory.md](references/tiered-memory.md).

**Skills.** Four, and each is a skill rather than a command because each has an entry no user types — a hook's stderr, a session start, an ending session, a token in a tool result.

- **`resolve`** — semantic merge of a diverged store, self-triggering on the `gitlore: memory merge prepared` directive a gate emits, and invocable as `/gitlore:resolve` for the entries where no directive reached an agent. A gate prepares the merge and yields; a sub-agent with fresh context synthesizes it (D9); the parent approves the summary and a continuation script composes, commits, and pushes when the flavor calls for it. A crashed merge leaves its state file behind, and every gate refuses to operate on top of one.
- **`push`** — publish every store to its own remote with no parent push, over `push-memory.sh`. No approval step: FR11 gated the content at commit time. Divergence loops through `/gitlore:resolve` and pushes again.
- **`merge`** — take what every store's remote holds and publish nothing, over `merge-memory.sh`. It is the only path by which a pinned tier advances (D43).
- **`recall`** — fetch specific memory bodies into context mid-task, from a trigger the user's prompt never carried. The agent picks up to five entries from the index it already holds and Reads those bodies in one batch. No hook, no request file, no state (D18).

The two merge skills' step-by-step is in [docs/references/merge-and-resolve.md](references/merge-and-resolve.md), `push`'s in [docs/references/commit-gate.md](references/commit-gate.md).

**Claude Code hooks.** `SessionStart` is the self-healing pass and does the most work: it warns when the launcher did not run, re-pins the five plugin-path keys, re-emits the hook wrappers and the FR11 gate, replays the hook-manager sentinel, materializes the store and its tiers and detaches each at `live`, composes the indexes, and emits the standing orientation on `additionalContext`. It is also where a new worktree's memory worktree is created, lazily, which is what makes worktree support uniform across `claude --worktree`, plain `git worktree add` and the Desktop button — no `WorktreeCreate` hook is registered. `WorktreeRemove` tears the memory worktree back down, advisory only. The rest are single-purpose: `PostToolUse(Bash)` nudges for a commit summary once per dirty episode (the FR11 opening), `PostToolBatch` acts on the two intent files and reports a mid-session plugin upgrade (D21), the `PreToolUse`/`PostToolBatch` index pair keys on what changed rather than on what the call declared (D31), and `PostToolUse(EnterWorktree|ExitWorktree)` guards against in-process worktree drift (D15). `SessionStart` and `PreCompact` re-arm the once-per-episode notices.

`SessionStart`'s steps and the worktree hooks are in [docs/references/installation.md](references/installation.md); the nudge and the intent-file hooks in [docs/references/commit-gate.md](references/commit-gate.md); the index pair in [docs/references/tiered-memory.md](references/tiered-memory.md).

**Git hooks.** `pre-commit` commits every dirty tier, then memory, advances each store's local `live`, and stages the memory gitlink into the index git handed it — so the parent commit records the pointer its own hook just created. `pre-push` publishes in the same order, tiers before memory. Both stand down rather than block a parent git operation: they exit 0 when the repo has no memory submodule and when its worktree is absent, and `pre-commit` stands down during a rebase, cherry-pick or revert, which re-creates commits authored earlier and would re-pin history to today's memory. Both clear git's full local-env-var set first, or a `git -C <submodule>` inherits the parent's scoping and redirects the submodule's refs into the parent's store. Divergence at either gate prepares a merge and yields to `/gitlore:resolve`.

**Entry points.** `commit-memory.sh` and `push-memory.sh` are callable scripts rather than hooks, so a skill can satisfy FR11 or FR8 at an interactive moment with no parent commit or push in flight (D16, D20). Each is discovered through a git-config key — `gitlore.commitCommand`, `gitlore.pushCommand` — so a caller needs one lookup and no knowledge of gitlore's layout (D5). Both share their body with the git hook that does the same job, which is what keeps the tier-before-memory ordering FR8 rests on from drifting between the two paths.

The git hooks' orderings, both entry-point contracts, and the placeholder-remote marker are in [docs/references/commit-gate.md](references/commit-gate.md).

### Hook Manager Support

The wrappers have to run whether the project drives git hooks through Lefthook, Husky, Overcommit, or nothing at all. Detection picks one by first match, wiring is idempotent behind a `# gitlore: managed` marker, and the command that produced it is stored in the sentinel so `SessionStart` can replay it on a clone or a new machine. Two sentinel values are keywords rather than commands: `direct`, which writes shell stubs into the repo's own hooks dir and is the default whenever no manager is recognized — the shared hooks dir exists in every git repo, so FR8's double-commit guarantee is active out of the box rather than waiting on a manual step — and `manual`, which prints a snippet and modifies nothing, reached only when detection is ambiguous or a user sets it by hand.

What differs per manager is only how the wrapper command is spelled and whether a shell expands it, since every one of them reaches it through `$(git rev-parse --git-common-dir)/gitlore-<hook>` rather than a literal path (D11). The detection table and each manager's wiring syntax are in [docs/references/installation.md](references/installation.md).

### Workflows

**Commit (happy path, agent-driven)**

1. Claude edits memory files during the session (ambiently, throughout).
2. When preparing to commit, Claude runs the configured pre-commit command as part of its workflow (via `Bash`).
3. PostToolUse hook fires — memory is dirty, commit-msg absent or stale.
4. Claude summarizes pending memory changes in prose and presents the summary. The user reviews the full diff in their own git tooling if they wish, then gives explicit confirmation.
5. Claude writes the confirmed summary to the commit-msg file.
6. Claude runs `git commit`. The preceding confirmation of the commit message covers the commit itself.
7. pre-commit hook: commits every dirty tier and advances each tier's `live`, then commits memory with the commit-msg file, deletes the file, and ff-pushes `HEAD` → `live`.
8. The hook stages the memory gitlink, so the parent commit records the pointer its own hook just created.

**Push (happy path)**

1. User or Claude runs `git push`. Agent-initiated push is allowed under the auto permission mode (subject to user approval of that mode).
2. pre-push hook: pushes each tier's `live` to its own remote, then memory `live` → `origin/live`.
3. Parent push proceeds.

**Tier write**

A portable fact authored into `memory/<tier>/` rides the ordinary commit flow: the tier is committed and its `live` advanced before memory's own `add -A`, so the memory commit records the moved gitlink rather than lagging it, and the tier is pushed before memory is. One approval summary covers the whole episode, grouped by destination — a line bound for a shared tier is more public than one bound for project memory.

**Publish without a parent push**

1. The user runs `/gitlore:push`, or a session that committed memory is ending with no parent push in sight.
2. The skill runs `push-memory.sh` through the `gitlore.pushCommand` key.
3. Each tier's `live` goes to its own remote, then memory's — the same order `pre-push` uses, from the same shared body.
4. The skill relays which stores moved and how far, and names any uncommitted memory as unpublished.
5. On divergence: `/gitlore:resolve` merges the store that diverged, then the skill pushes again, until the command exits 0.

**Resolve (on divergence) — primary path: agent-driven**

Most divergence is detected while the agent is attempting commit or push. The agent sees the hook's exit-1 stderr (addressed to it via the `$CLAUDECODE` branch) and invokes `/gitlore:resolve` inline without user intervention; the skill's five steps are in [docs/references/merge-and-resolve.md](references/merge-and-resolve.md). It ends by advancing `live` — and, for a remote-flavored merge, `origin/live` — leaving HEAD detached at the new `live`, refreshing the parent's context with the incoming diff (or directing the user to `/clear` when resolve ran at session start), and retrying the original commit or push.

**Resolve fallback: user-driven**

If divergence surfaces outside a Claude session (`git commit` or `git push` run from a plain terminal), the hook's stderr directs the user to open this project in Claude Code and run `/gitlore:resolve`. The primary path resumes from there.

**Clone**

`git clone --recurse-submodules <repo>` → the first `SessionStart` configures settings, detaches memory at `live`, and replays the hook-manager sentinel.

Without `--recurse-submodules`: `SessionStart` detects the uninitialized submodule and runs `git submodule update --init`. That leaves the memory submodule at a **detached HEAD** on the recorded gitlink SHA with only the remote-tracking `origin/live` — no local branches. Since the branch-model logic references `live` as a *local* ref (checkout source and ff-merge target), `SessionStart` first materializes a local `live` from `origin/live` (falling back to the checked-out `HEAD` when memory has no remote), then proceeds as above. Without it the first post-clone session dies on `fatal: 'live' is not a commit`.

**Worktree creation** — `SessionStart` in the new worktree initializes the memory submodule worktree, detached at `live`. Uniform across `claude --worktree`, manual `git worktree add`, and the Desktop button (all start a session in the worktree). Why no `WorktreeCreate` hook is registered is in [docs/references/installation.md](references/installation.md).

### Remote Repository

The memory submodule is pushed to a dedicated remote of its own. Every default is inherited from the parent's `origin` — name (`<parent-remote-name>-memory`), owner, and visibility — on the reasoning that memory is auxiliary to the project and there is no reason to split access control; each is overridable at creation time. A parent with no remote gets no memory remote, and memory stays local-only, which is a supported end state rather than a half-finished install.

Creation is disclosed before it happens: the proposed name, owner and visibility, plus a notice that memory may carry any context Claude recorded. That disclosure is orientation, not a clearance gate — the effective gate is the per-commit review (FR11). Creation that fails for any reason (auth, quota, network, name collision) degrades to copy-paste instructions rather than aborting the install.

Per NFR5 (double-commit semantics), memory `live` is pushed before the parent push on every `git push`, so the parent remote always names a submodule SHA reachable on the memory remote.

The naming, ownership and visibility rules in full, and the per-provider creation methods, are in [docs/references/installation.md](references/installation.md).

---

## Design Decisions

Grouped by theme. Each group's argument — what was weighed, what was rejected, and why — is in a reference file; the conclusions are here, so a proposal to change one meets the decision in this doc and reaches its reasoning in one hop.

**Merge and resolve.** The branch model and the divergence path: what the trunk is, which side of a merge is authoritative, and how the work splits between the scripts and the agent. Arguments in [docs/references/merge-and-resolve.md](references/merge-and-resolve.md).

- **D1** — `live` is the memory trunk, independent of the parent's default branch
- **D2** — superseded by D41's detached-at-`live` model; kept for the record
- **D3** — ordinary checkout during resolve, not git plumbing
- **D6** — merge direction: the more-authoritative side is the first parent
- **D7** — scripts decide, the agent handles language
- **D9** — a sub-agent synthesizes the merge (requires the experimental flag)
- **D13** — a lock-contention retry wrapper guards mutating memory git calls
- **D24** — a directive that names a sub-agent carries its own authorization

**The commit gate.** FR11's approval machinery, and the two standalone entry points that satisfy it without a parent commit or push. Arguments in [docs/references/commit-gate.md](references/commit-gate.md).

- **D4** — the commit message travels by file handshake; its presence is the approval signal
- **D8** — remote creation requires explicit user confirmation
- **D12** — a submodule-side commit gate backs FR11 as defense in depth
- **D16** — a standalone, arg-driven memory-commit entry point
- **D19** — one canonical approval clause, discovered externally via a git-config key
- **D20** — a standalone push entry point the skill calls directly, with no trigger file
- **D22** — the memory-hygiene checker is a repo-local gate, not shipped surface

**Install, hooks and the session.** Where the wrappers live and how they are anchored, why the redirect is injected at launch, and what SessionStart says to whom. Arguments sit alongside the wiring they explain, in [docs/references/installation.md](references/installation.md).

- **D5** — wrapper scripts live in the git common dir, untracked
- **D10** — the memory redirect is a launch-time `--settings` shim, not project settings
- **D11** — wrapper paths are gitlink-aware, anchored at the common dir, for linked worktrees
- **D14** — user-facing SessionStart output goes on `systemMessage`
- **D21** — a mid-session plugin upgrade is a notice, not a self-healing config
- **D25** — direct wiring refuses rather than appends after an existing `exec`

**Claude Code platform workarounds.** Three decisions whose subject is a harness behaviour rather than gitlore's own design. Each carries the empirical work that established the behaviour, which is what makes them long and what makes them worth keeping whole. Arguments in [docs/references/cc-platform.md](references/cc-platform.md).

- **D15** — an in-process-worktree memory-drift guard
- **D18** — active recall is a skill the agent runs itself, with no hook and no state
- **D23** — the `Edit` weld defect is contained by a pair that computes the intended result, repairs, and reports its own obsolescence

**D17 — Tiered memory (FR15): nested submodules plus structural index composition**

FR15 calls for shared tiers (a truly-global `lore`, an org-scoped `ddaanet`, …) surfacing in *every* participating repo alongside its local memory, without a flat merge that would blow the always-loaded index budget. Across N sibling repos, `user`, CC-platform `reference` and portable `feedback` facts duplicate and drift, while `project` facts are correctly repo-local. The design keeps Anthropic's memory structure — index, files, agentic recall — and upgrades only gitlore's *composition* of the root index.

The mechanism is a subsystem rather than a single call: its decisions (**D26 through D44** — retrieval and routing, index composition, the authoring-time sync, and tier stores and merges) live in [docs/references/tiered-memory.md](references/tiered-memory.md), split out because the cluster runs to ~47 KB and is only needed when touching this subsystem specifically.

---

## Rejected Alternatives

Grouped by the part of the system they belong to. Each entry states the alternative and why it was ruled out; a decision that was later inverted lives in the changelog, not here.

### Branch model and merge

**`live` as a working branch, in any store or worktree.** `live` is the trunk every store fast-forwards onto and no store ever checks out as a branch. Working on it directly would make concurrent sessions compete for one ref and would re-introduce the one-checkout-per-branch collision the detached model exists to avoid.

**`git commit-tree` + `git update-ref` for the resolve merge.** Low-level plumbing to avoid checking a branch out. Unnecessary — the merge prepares with `checkout --detach <authority>`, which is ordinary porcelain, easier to reason about, and cannot collide with another worktree because nothing is ever checked out as a branch (D3, D41).

**A temporary worktree for resolve.** Indirection with no payoff; the store's own worktree is where the merge belongs.

**`claude --print` for conflict resolution.** No session context, no way to ask the user, no memory of what produced the changes.

**Single-agent resolve with a post-hoc context refresh.** The parent's in-memory picture of the files is pre-merge and stale the moment git rewrites them on disk. A sub-agent reads the post-merge state fresh (D9).

### The commit gate

**A `Stop` hook to generate the commit message.** Fires on every response turn rather than at commit intent — noise, and the wrong timing for a confirmation gate.

**`PostToolUse` on every memory `Write`/`Edit`.** Couples commit preparation to individual edits instead of to commit intent. The configured pre-commit command is a far stronger signal with cleaner timing. (D31's `PostToolBatch` composition is a different use of the same event: structural placement, no commit semantics.)

**An interactive prompt inside the `pre-commit` hook.** Blocks non-interactive commits from CI and scripts; agent-mediated confirmation costs nothing there.

**An in-session diff dump for commit review.** Too noisy in the TUI. The user reviews the diff in their own git tooling and approves the prose summary.

**A `PreToolUse` hook constraining the agent's git operations.** Belt-and-braces with real scoping complexity at the CC level. The drift it anticipated did happen — a direct submodule commit bypassed FR11 — and the fix was a submodule-side `pre-commit` gate, consistent with the rest of the hook architecture rather than layered on top of it (D12).

**Triggering a memory commit through a parent commit** (pointer bump, `--allow-empty`, or unstaging everything else). All of them fight the hook's parent-commit requirement and the gitlink-staging wrinkle, and drag whatever else is staged. The standalone entry point sidesteps all of it (D16).

**Reimplementing the sentinel, `push HEAD:live` and merge-state logic in a caller.** Fragile duplication of gitlore internals that would drift from `pre-commit`. The logic stays in `commit-memory.sh`; callers resolve it via `gitlore.commitCommand` (D16).

**A caller that pre-writes the commit-message file, with the entry point only validating freshness.** Couples external callers to a gitlore-internal path and keeps two approval semantics alive. Arg-driven (`-m`/`-F`) keeps the IPC handshake internal and gives callers one `git commit`-shaped contract (D16).

### Hooks, wrappers and install

**Tracked hook scripts in the repo.** Commit churn on every plugin update, and it couples the repo's history to the plugin's versioning.

**A literal `.git/gitlore-<hook>` wrapper path.** Fails in a linked worktree, where `.git` is a gitlink file: the write aborts SessionStart and the exec blocks the commit. Replaced by the common-dir anchor (D11).

**A per-worktree wrapper anchor** (`--git-path gitlore-<hook>`). Reintroduces the commit-blocking gap in any worktree where no session has run, because the shared wired stub would exec a per-worktree wrapper that does not exist. The common-dir anchor has no such gap (D11).

**A `WorktreeCreate` hook to set up the memory worktree.** It is an override hook — it fires before the worktree exists, must create it, and must print only its path (extra stdout hangs CC, #27467) — carries no branch in stdin, and never fires for Desktop-created worktrees. `SessionStart` in the new worktree covers every case with none of that (verified CC 2.1.150).

**A strictly non-empty initial commit at install.** Install passes `--allow-empty` as a safety net: the commit normally carries migrated auto-memory or a `MEMORY.md` scaffold, but a prior failed install can leave the migration source a stub, and a hard failure there helps nobody.

**`gh repo create` as the only remote-creation method.** Locks out non-GitHub users; the provider-agnostic copy-paste flow covers them.

**A version-less plugin pointer, resolved at hook runtime.** Pointing the five `gitlore.*` keys at a symlink refreshed per lookup would let git-side hooks follow an upgrade mid-session while CC-side hook registration, skill bodies and agent definitions stayed on the version the process froze at — a split-version session, worse than uniform staleness, which has one failure mode and one remedy (D21). The premise is also wrong: installs are pinned per scope and per project, not globally, so "the newest directory in the cache" is not what a given repo loads.

**Wrappers self-healing from `CLAUDE_PLUGIN_ROOT`.** That variable is exported to Claude Code hooks only. A git hook fires from agent Bash, where it is unset, so the wrapper has nothing to heal from — and the split-version objection above stands regardless (D21).

**A separate `gitlore.memoryPath` config key.** `.gitmodules` plus the fixed submodule name `gitlore-memory` is already canonical; a second source is a divergence risk.

**Making the memory push optional in v1.** Gitlore without shared memory is a diminished product. An opt-out can be added later as a preference.

### Memory redirect

**`autoMemoryDirectory` in `.claude/settings.json` or `.claude/settings.local.json`.** Silently ignored — CC honours the key only from `policySettings`, `flagSettings` and `userSettings`, never a project tier. Observed, not inferred: with the key written there, memory lands in the default directory and nothing reports the discard (D10).

**`autoMemoryDirectory` in global `~/.claude/settings.json`.** Honoured, but global: every project's auto-memory would redirect into one repo's submodule.

**`CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` via `.envrc`.** Highest precedence and per-project scopable, but it carries cowork semantics — it disables the native memory-write auto-allow and can inject cowork guidelines into the system prompt. `--settings` feeds the identical setting with none of that (D10).

**An explicit `gitlore` launch command instead of shadowing `claude`.** Breaks the value proposition: users would have to remember a new command. The shim keeps them typing `claude`.

### Tiered memory and index composition

**A flat merge-everything store** (one shared directory for all repos). Blows the always-loaded root-index budget and loads N irrelevant projects' facts every session. Recall is on-demand, so a large tier is free *if* it is surfaced by selection — tiered composition keeps bodies on-demand and splices only pointers into the root index (D29).

**A content classifier routing each new fact to global-vs-project.** Puts model reasoning on the write path to inspect a fact's content. Where to file a fact you are already authoring is a generation choice: the agent picks the directory, the directory is the submodule (D28).

**Frontmatter `description` as the source of truth for the index one-liner.** The two surfaces drift bidirectionally — the agent revises whichever one it has loaded, and the other rots, in both directions. Deriving the index from frontmatter would overwrite curated one-liners with stale text and degrade the *reliable* retrieval lever. The index line is canonical; frontmatter drift is healed by the one-way authoring-time sync (D26, D38).

**An append-only constraint on shared-tier indexes.** Unnecessary. Concurrent insertions merge through the same semantic path as any memory divergence, and distinct per-index namespaces prevent cross-index collision, so conflicts resolve without constraining where the agent may insert (D44).

**A `merge` driver plus `.gitattributes` for the entry-wise index merge.** The driver has to be configured per *clone* — `memory/`, every tier, every linked worktree's tier clone — and when the pin goes stale git falls back to a text merge **silently**, which is the exact failure the entry-wise pass exists to prevent. gitlore drives every memory merge itself, so the pass has a guaranteed call site and no per-clone configuration (D44).

**`**/MEMORY.md merge=union` plus a dedup-by-path pass.** The union driver concatenates blindly and manufactures the duplicate lines the dedup then cleans — solving a problem it creates (D44).

**Propagating the root index down into the carriers during the merge continuation.** The adoption there is up-only, for two independently sufficient reasons: the merged tier's facts must reach the root because that is the only surface recall reads, and projecting down writes a second store the user never reviewed as a side effect of approving one index. In-session propagation is the hooks' job (D36).

**Recompose owning index-line presence — coverage (seed a missing pointer from frontmatter) and prune (drop a bullet whose file is gone).** Both are refused by the presence-authority rule: the index is authoritative over a line's presence, and no surface is auto-edited to match the other. Coverage resurrects a line the user deliberately removed; prune inverts the authority and destroys what may be the last trace of a lost memory. Each also hardcodes a semantic call — was this deletion deliberate? — that belongs to the agent (D34).

**Deleting a memory file when its pointer line is removed.** Prune's mirror image, refused for the same reason index authority is non-destructive: a destructive edit as the silent consequence of an index edit is the one surprise a memory store must not spring, and the file is the only place the fact still lives. Unlisting a fact and destroying it are different acts (D34).

**Scoring an index hook against its body, tf-idf style,** to flag a line with no routing value. Refuted on the real store: over 76 documents `df ≤ 3` marks ordinary prose words as distinctive, so the score tracks hook *length* rather than quality (means 2.06 `reference` vs 1.76 `feedback` — no separation). Document frequency needs a corpus a memory store will never have. The two countable advisories — byte budget and missing trigger token — cover what is checkable (D39).

**A `SessionStart` warning when a tier is mounted without a paired guard plugin.** gitlore models no dependency from a memory tier to any plugin, and inventing one would be wrong in the general case: prohibitions are per-project, each repo carrying the set its own work needs, so a tier mount is no evidence about which guards that repo should have. The warning would also make gitlore the enforcement point for a second plugin's installation, reading `enabledPlugins` — a record of what the user chose — as a defect report.

### Active recall

**Hook-side injection of the bodies**, from a request file the agent writes: `.claude/gitlore-recall` listing up to five store-relative paths, a `PostToolBatch` hook validating and resolving it, and a content-addressed ledger so a body already in context was never sent twice. It delivers unconditionally, which a directive cannot — but `additionalContext` spills past ~2KB into a pointer file, and injected bytes never satisfy the `Read`-before-`Edit` ledger, so the common case (recall a fact, then correct it) paid for the body twice and the large case delivered a preview. The validation, the ledger and its two reset events existed only to serve that channel; the selection judgement they surrounded was always the agent's (D18).

**A `PreToolUse` deny on the first durable write of an episode,** forcing a recall decision before the agent may write. Making a denial the *normal* control flow spends a turn on every editing episode forever and trains the agent to read denials as routine, corroding the channel that should mean stop. Arming it at `UserPromptSubmit` is worse still: it duplicates the native classifier that already fires there. The obligation lives in the calling skill's flow instead (D18).

---

## Changelog

How the design got here is recorded in [changelog.md](changelog.md), newest first.
