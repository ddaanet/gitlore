# gitlore Design Document

gitlore is a Claude Code plugin that makes Claude's auto-memory versioned, shared
and git-backed. Memory lives in a git submodule inside the project repo, every
memory commit passes a user-approved review gate, and portable facts are shared
across repos through nested *tier* submodules.

This is the living design: what the system does, how it is built, and why it is
built that way. It is kept in the present tense — how it got here is in
[changelog.md](changelog.md). Plans live in `docs/plans/`, reference material in
`docs/references/`.

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
8. Memory is pushed to a dedicated remote repository with double-commit semantics — memory `live` is pushed before the parent push on every `git push`. It is also publishable on its own, with no parent push and no `git` command typed by hand, so a session that commits memory and ends does not leave those facts in the local clone only. *(Mechanism in D20.)*
9. Remote creation is provider-agnostic; `gh` CLI is used opportunistically when available.
10. **Install-time disclosure (informational).** Before creating the memory remote, the user is shown the proposed name, owner, visibility, and a notice that memory may contain session context. This is orientation, not a hard gate.
11. **Per-commit review gate.** Every memory commit (including merge commits produced by `/gitlore:resolve`) requires explicit user approval of a prose summary before the commit message file is written and the commit executes. This is the effective control over what reaches the remote.
12. **Coexistence.** Repos without a `gitlore-memory` submodule are unaffected when the plugin is present. All hooks no-op silently if the submodule is not registered.
13. **Recovery.** If memory enters a broken state (missing `live`, partial merge, locked checkout), tooling surfaces a clear error with recovery instructions rather than blocking parent git operations silently.
14. **Transparent per-project redirect.** Memory is redirected into the submodule without changing how the user invokes Claude Code — they keep typing `claude`, using CC's native auto-memory. The redirect is scoped to the project (no effect on other repos' memory) and applied at launch by the Memory Redirect Launcher.
15. **Tiered memory.** Portable facts (user-level, Claude Code platform `reference`, durable cross-project `feedback`) are shared across participating repos through one or more shared *tier* repos — e.g. an organization tier and a global tier — surfacing alongside the repo's own memory; `project` facts stay repo-local. Tiers are additive and composed, never flattened into a single merged store. *(Mechanism in D17.)*
16. **Active recall.** A memory body can be fetched into context on demand, mid-task, from a trigger the user's prompt never carried — an error string in a tool result, a flag in a file just read. The agent names the entries it wants; the tooling does the reading. *(Mechanism in D18.)*

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
10. **The gate is cheap enough to run on every commit.** Not currently met. `just precommit` — `check-version lint test` — runs 530 s over 620 cases (measured 2026-07-29 on the 2-vCPU dev droplet, `--jobs 2`). The machine is part of the figure: `user + sys` came to 566 s against 530 s wall, so the suite is barely parallel and more cores would not divide the number. The input-hash sentinel caches a green result, so the full cost is paid precisely when a change is in flight, which is when it is most in the way. Making the suite faster is open work, and cutting per-case work is the lever rather than raising `--jobs`; `bats -T` reports per-test timings, so the breakdown comes free on the next full run rather than needing a profiling pass of its own.
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
- **Two divergence gates, one shape.** A store's pending HEAD against its own local `live` (`pre-commit`), and its local `live` against its own `origin/live` (`pre-push`). Both reduce to "my pending commit vs the authoritative side", which is why one merge machinery serves memory and tiers alike (D6, D17).
- **Parent branch switches, rebases and force-pushes are independent of memory.** Memory history is its own concern; nothing in the parent's ref layout is mirrored.

### Configuration

Configuration splits three ways by what has to travel: tracked files travel with the repo, git-config keys are per-clone and machine-local, and the IPC files are transient handshakes between the agent and the hooks.

**Tracked — travels with the repo.** `.claude/settings.json` carries `gitlore.enabled: true` (the activation flag every hook guards on) and `gitlore.precommitCommand`, the project's own pre-commit check (e.g. `lefthook run pre-commit`) that the `PostToolUse` nudge watches for. `.gitlore/bin/claude` is the launcher shim and `.envrc` puts it on `PATH` (`source_up_if_exists` plus `PATH_add .gitlore/bin`) — see Memory Redirect Launcher. `.claude/gitlore-hook-setup` is the hook-manager sentinel, below. Inside the memory submodule, `memory/.gitlore-tiers` lists the active tiers in precedence order (D17).

**Local git config — never tracked, re-pinned every session.** Four keys point at the installed plugin, whose cache path changes on every upgrade: `gitlore.hooksDir` (the hook scripts the wrappers exec), `gitlore.commitCommand` (`commit-memory.sh`, D16), `gitlore.pushCommand` (`push-memory.sh`, D20) and `gitlore.memoryApprovalClauseFile` (the canonical approval wording, D19). All four are seeded at install and re-written by every `SessionStart`, which is what makes them self-healing; each consumer verifies the resolved path before using it rather than trusting the key (D5).

**IPC files — the agent writes, a hook acts.** `.claude/gitlore-memory-message` (the approved commit summary), `.claude/gitlore-commit-memory` (standalone-commit trigger), `.claude/gitlore-add-tier` (mount intent) and `.claude/gitlore-recall` (recall request) all sit in the parent working tree, gitignored. They live there rather than in a gitdir because a gitdir write is blocked by the CC sandbox and read as self-configuration by the auto-mode classifier — the agent can write an ordinary project file and nothing else. Hook-owned state that the agent must *not* write goes the other way, into the store's gitdir: the once-per-episode nudge marker `gitlore-nudged`, the recall ledger, and the merge-state file.

> **No `autoMemoryDirectory` in project settings.** Claude Code resolves `autoMemoryDirectory` only from `policySettings`, `flagSettings` (the `--settings` flag), or `userSettings` (`~/.claude/settings.json`) — never from project-level `.claude/settings.json` or `.claude/settings.local.json`, which it discards for security. The per-project redirect is therefore injected at launch by the Memory Redirect Launcher, not written to a settings file. See D10.

**Commit message file:** `.claude/gitlore-memory-message`, resolved by `gitlore_commit_msg_file` from the superproject working tree (`git -C <memory-path> rev-parse --show-superproject-working-tree`). Claude writes it once the user has confirmed the commit summary; the commit hook consumes and deletes it. Its presence is the signal that a memory commit carries approval (D4).

**Sentinel file:** `.claude/gitlore-hook-setup` — tracked. Contains the hook setup command or keyword (`lefthook install`, `npx husky`, `overcommit --install`, `direct`, or `manual`). `SessionStart` replays it to re-wire hook-manager integration on a clone or a new machine.

**Hook wrappers:** `SessionStart` writes two flat files into the repo's **git common dir** on every startup, resolved via `git rev-parse --git-common-dir`:

- `<common-dir>/gitlore-pre-commit`
- `<common-dir>/gitlore-pre-push`

**Why the common dir, not `.git/` literally.** In a linked worktree `.git` is a gitlink *file*, not a directory, so a literal `.git/gitlore-*` path fails on both sides: the write aborts SessionStart, and the shared wired hook `exec`s a path that does not exist and blocks the commit. The common dir is shared across all worktrees (`--git-common-dir` → `.git` in the main worktree, `<main>/.git` in a linked one), so one emission is reachable and executable from every worktree — including one where no Claude session has ever run (a plain `git worktree add` followed by a `git commit`). Every producer (`emit-wrappers`) and every consumer (the wired stubs and manager configs) resolves the wrapper through `--git-common-dir`; none hardcode `.git/`. See D11.

Each wrapper delegates to the current plugin via `git config gitlore.hooksDir` (regular git config, shared across worktrees via the common config). Stable paths for hook manager configs; plugin updates are transparent. If `gitlore.hooksDir` is unset (a plain `git commit` outside any Claude session before SessionStart has fired), the wrapper exits 0 after emitting a stderr hint — `"gitlore skipped: hooks not installed"` plus instructions to install the marketplace, plugin, and start Claude.

```sh
#!/bin/sh
HOOKS_DIR=$(git config gitlore.hooksDir 2>/dev/null)
if [ -z "$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
if [ ! -x "$HOOKS_DIR/pre-commit" ]; then
  echo "gitlore skipped: hooks dir is stale (plugin upgraded; cache GC'd)." >&2
  echo "Start Claude Code in this repo to refresh the hooks dir, then retry." >&2
  exit 0
fi
exec "$HOOKS_DIR/pre-commit" "$@"
```

### Memory Redirect Launcher

Claude Code's native auto-memory writes to `~/.claude/projects/<sanitized-cwd>/memory/` unless `autoMemoryDirectory` is set in an honored settings tier. Project settings are *not* honored (D10), so the only per-project, non-global mechanism is the `--settings` flag at launch. The launcher is a thin `claude` shim that injects it transparently — the user keeps typing `claude`, and memory lands in the submodule.

**One shim, two placements.** The shim body is identical in both modes; only how it lands on `PATH` differs. It is `#!/usr/bin/env sh`:

```sh
#!/usr/bin/env sh
# real claude = next `claude` on PATH after stripping my own dir
self=$(cd "$(dirname "$0")" && pwd)
newpath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$self" | paste -sd:)
real=$(PATH="$newpath" command -v claude) || { echo "gitlore: real claude not found" >&2; exit 127; }

# already injected upstream? pass through (composability, anti-double-inject, anti-recursion)
[ -n "$GITLORE_LAUNCHED" ] && exec "$real" "$@"

# opt-in: load the plugin from the checkout you're standing in, not the marketplace cache
if [ -n "$GITLORE_AUTO_CLAUDE_PLUGIN_DIR" ] && [ -f .claude-plugin/plugin.json ]; then
  set -- --plugin-dir . "$@"
fi

# in a gitlore-enabled repo? cheap git checks first, so jq only runs for actual gitlore repos
root=$(git rev-parse --show-toplevel 2>/dev/null)
mempath=$(git config --file "$root/.gitmodules" submodule.gitlore-memory.path 2>/dev/null)
[ -n "$root" ] && [ -n "$mempath" ] || exec "$real" "$@"          # no gitlore submodule → passthrough
[ "$(jq -r '.gitlore.enabled // false' "$root/.claude/settings.json" 2>/dev/null)" = true ] \
  || exec "$real" "$@"                                            # submodule present but disabled → passthrough

json=$(jq -nc --arg p "$root/$mempath" '{autoMemoryDirectory:$p}')
export GITLORE_LAUNCHED=1
exec "$real" --settings "$json" "$@"
```

- **Real-claude resolution.** The shim strips its own directory from `PATH`, then takes the next `claude`. That next entry is normally Claude Code's own version-selector launcher (`~/.local/bin/claude`), so version selection is preserved — the shim chains to it rather than pinning a version.
- **`GITLORE_LAUNCHED` sentinel.** Set before exec. Does triple duty: (a) when both shims are on `PATH`, the repo-local one runs first, execs the global one which sees the sentinel and passes through — no double injection; (b) guards against any accidental recursion; (c) lets `SessionStart` detect a plain `claude` launch (sentinel unset) and warn loudly instead of silently stranding memory.
- **`GITLORE_AUTO_CLAUDE_PLUGIN_DIR` (opt-in, default off).** When the var is non-empty *and* the cwd holds a `.claude-plugin/plugin.json`, the shim prepends `--plugin-dir .`, so Claude Code loads the plugin from the checkout you are standing in rather than the marketplace cache — which lags the repo at the same version string, making plugin changes untestable without a reinstall. Default-off is the point: silently shadowing an installed plugin whenever a user cd's into its source tree would be surprising and could mask a released version with dirty working-tree code. Opting in is a one-line rc export for people who develop plugins. Injected via `set -- --plugin-dir . "$@"` before the repo checks, so it applies on every exec path (passthrough included) — a plugin checkout need not be a gitlore repo. The `GITLORE_LAUNCHED` sentinel still short-circuits first, so an upstream shim's decision wins.
- **Path built with `jq`.** Handles spaces/quoting safely; computed at runtime so committed shims stay portable across clones. `--settings` loads an *additional* settings tier (`flagSettings`), so only `autoMemoryDirectory` is overridden; all other settings still resolve from their normal tiers.

**Placement A — repo-local, direnv (default).** `/gitlore:install` emits two **committed** files: `.gitlore/bin/claude` (the shim) and `.envrc`. The `.envrc` must put `.gitlore/bin` at the **front** of `$PATH` so the shim shadows the real `claude` (shim before payload). direnv's `PATH_add .gitlore/bin` prepends, which is exactly this. When creating `.envrc` from scratch, `source_up_if_exists` is written as the first line so parent-directory direnv configs are inherited. Subtlety with an existing `.envrc`: direnv evaluates top-to-bottom and each `PATH_add` prepends, so the *last* `PATH_add` wins the front slot — gitlore's line must be inserted after any pre-existing `PATH_add` (idempotent no-op if already present). After a one-time `direnv allow`, the shim is on `PATH` only inside the repo tree (subdirectories included). Both files travel with the repo, so every clone gets the transparent launcher after `direnv allow`. The path is namespaced under `.gitlore/bin/` to avoid colliding with a project's own `bin/`.

**Placement B — global shim, no-direnv fallback (automatic).** When direnv is not found during install, `run.sh` automatically runs `scripts/install/global-shim.sh`, which drops the *same shim* at `~/.gitlore/bin/claude` and **prints** (does not auto-append) the one `PATH` line for the user's shell rc (e.g. `set -gx PATH ~/.gitlore/bin $PATH` for fish). Per-repo installs never touch it otherwise. Because the gitlore-repo detection is generic, this one shim auto-activates in any gitlore repo and no-ops everywhere else. This covers users without direnv and launches from outside an allowed directory.

### Components

#### Commands

**`/gitlore:install`** — one-time setup, idempotent.

Precondition: must run from the **main worktree** (repo root). In a linked worktree the memory submodule is typically unchecked-out, so submodule git ops would silently escape to the parent repo — staging the parent's HEAD as the memory gitlink and creating branches in the parent. `run.sh` aborts when the per-worktree git dir differs from the common git dir. As a second line of defense, `init-submodule.sh` refuses to stage the gitlink when the memory path has no `.git` (registered but not checked out).

1. Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; if unset, warn and offer to enable it (required for sub-agent-based resolve).
2. Prompt for memory path (default: `memory`). If the path exists with unrelated content, refuse and prompt for an alternative.
3. Prompt for the project pre-commit command (stored as `gitlore.precommitCommand`).
4. Display install-time disclosure: proposed memory remote name, owner, visibility (inherited from parent), and notice that memory may contain session context. Await acknowledgement (informational, not a hard gate).
5. Create the memory remote with explicit D8 confirmation — see Remote Repository. `gh repo create` (or provider-appropriate method) runs. If the parent has no remote, skip; memory stays local-only.
6. `git submodule add <remote-url> <path>` (or a local path if no remote) — registers the submodule in `.gitmodules` and initializes the empty working tree.
7. Seed memory content inside the submodule worktree:
   - If existing auto-memory exists at `~/.claude/projects/<hash>/memory/`, copy it in.
   - Otherwise, scaffold a `MEMORY.md` index file.
8. `git -C <memory-path> add -A && git -C <memory-path> commit -m "Initial memory"` — non-empty initial commit; install is git-atomic.
9. Create the `live` branch at the initial commit and check the worktree out detached at it (the branch model — `live` is never checked out as a branch).
10. If a remote was created, `git -C <memory-path> push origin live` so the parent's submodule pointer is reachable upstream.
11. Write `gitlore.enabled: true` and `gitlore.precommitCommand` to `.claude/settings.json`.
12. Emit the memory redirect launcher: write `.gitlore/bin/claude` (shim) and ensure `.envrc` prepends `.gitlore/bin` to the front of `$PATH` via direnv `PATH_add .gitlore/bin` (create `.envrc` with `source_up_if_exists` on the first line, or insert the `PATH_add` line after any existing `PATH_add` so it wins the front slot; idempotent if already present). Both are staged for commit. Then activate the launcher: if direnv is available, run `direnv allow` (non-fatal — a read-only direnv dir is not a blocker); otherwise run `global-shim.sh` to install the global shim and print the `PATH` line for the user's shell rc. (Does **not** write `autoMemoryDirectory` to any settings file — that tier is ignored; see D10.)
13. Write `gitlore.hooksDir` (abs path to plugin hooks) to local git config.
14. Run hook-manager detection script → apply idempotent wiring, write sentinel file.
15. Leave tracked changes staged for the user to commit.

Idempotency rules for re-runs: existing submodule → verify and skip creation; existing settings keys → overwrite only if value differs; migration → detect prior migration (by presence of migrated files or a done-marker) and skip; existing hook-manager wiring with our marker → skip; existing remote → skip creation. A partial install (user aborted mid-flow) is recovered by re-running.

**`/gitlore:add-tier`** — mount an existing shared tier into this repo, or create a new one. The command only writes an intent file (`.claude/gitlore-add-tier`, `key=value`: `mode`, `name`, `url`, `description`); a `PostToolBatch` hook runs `scripts/add-tier.sh` on the agent's behalf, because mounting both mutates submodules (which the auto-mode classifier reads as self-modification) and clones over the network (which the agent's command sandbox has none of). See D17.

#### Skills

**`resolve`** — semantic merge of a diverged store. Self-triggering: a commit or push that fails with `gitlore: memory merge prepared` on stderr carries everything the skill needs, so the agent invokes it without being asked. It is also invocable as `/gitlore:resolve` for the three entries where no directive reached an agent — a health check after a compaction, a fresh session, or a divergence surfaced by a `git push` the user ran in their own terminal.

The division of labour is D7's: the script decides, the agent writes prose.

1. **A gate yields.** Whichever hook meets the divergence calls `gitlore_yield_merge`, which prepares the merge, writes a state file into the diverged store's gitdir, and emits the directive on stderr. Preparation pins the pending commit at `refs/gitlore/pending`, checks the authority out detached (so it becomes the merge's first parent, D6), merges the pending commit in with `merge.conflictStyle=diff3`, and re-merges every index file entry-wise (D17). One shape covers both flavors: `head-vs-live` (pending commit against local `live`) and `head-vs-remote` (against `origin/live`).
2. **The skill parses the directive** — the store path, the state file, and a verbatim continuation command — and dispatches the `gitlore:memory-merger` sub-agent. The sub-agent gets fresh context (D9), the two side diffs and the file tree (D17), synthesizes holistically whether or not git flagged a conflict, runs `git add -A`, and returns a prose summary. `No conflict.` is a valid answer.
3. **The parent approves** the summary — from session context where it can, escalating to the user only when it cannot judge — and resumes the sub-agent via `SendMessage`. A rejection re-synthesizes.
4. **The continuation** (`resolve.sh continue-after-merge`) composes the indexes, runs the dangling-pointer report, commits, and pushes when the flavor calls for it. It finds the prepared merge by walking the stores rather than assuming memory, and refuses outright if two are prepared at once.
5. **The skill loops** until `resolve.sh` exits 0 (a second flavor can be waiting), then retries the original commit and tells the user which store was merged — a tier is shared with other repositories, the project store is not.

A crashed merge leaves the state file behind. Every gate guards on it: with `MERGE_HEAD` present the directive says abort-then-retry; without it, the merge is dead and the message says manual intervention is required rather than operating on top of it.

**`push`** — publish every store to its own remote with no parent push. Front door is `/gitlore:push`, but it is a skill rather than a command because its second entry is contextual: a session that committed memory and will make no parent push has to reach for it unprompted, and only a description is matched against context. The body makes one call — `bash "$(git config gitlore.pushCommand)"` — and reads the exit: `0` relays the report, a non-zero carrying `gitlore: memory merge prepared` loops through `/gitlore:resolve` and pushes again, any other non-zero is surfaced verbatim. There is no approval step; FR11 gated the content at commit time. See D20.

**`recall`** — fetch specific memory bodies into context mid-task, from a trigger the user's prompt never carried. The agent writes up to five store-relative paths (or `no match`) to `.claude/gitlore-recall`; a `PostToolBatch` hook reads them and emits the bodies as `additionalContext`. See D18.

#### Claude Code Hooks

**`SessionStart`**

Guards: if `gitlore.enabled` is not `true`, or `.gitmodules` has no `gitlore-memory` entry, no-op.

1. **Launcher guard.** If `GITLORE_LAUNCHED` is unset, the session was started with a plain `claude` — memory is *not* redirected and will strand in the default directory. Say so on `systemMessage`, naming the fix (`direnv allow`, or the global shim on a machine without direnv). Nothing is written to any settings file; that tier is ignored (D10).
2. **Re-pin the four plugin-path keys** — `gitlore.hooksDir`, `gitlore.commitCommand`, `gitlore.pushCommand`, `gitlore.memoryApprovalClauseFile` — so a plugin upgrade heals itself.
3. **Emit the wrappers** `gitlore-pre-commit` and `gitlore-pre-push` into the git common dir, and the FR11 commit gate into the memory store and each tier. Idempotent and worktree-agnostic (D11, D12).
4. **Replay the hook-manager sentinel** to reinstate wiring after a clone or a new machine (`direct` and `manual` are keywords, not commands — see Hook Manager Support).
5. **Materialize the store.** Initialize the submodule if needed; add a memory worktree for a linked parent worktree; create local `live` from `origin/live` (or from the checked-out gitlink when there is no remote) after a clone without `--recurse-submodules`, since the branch model references `live` as a local ref.
6. **Detach at `live` and fast-forward**, or skip the fast-forward with a notice when memory is dirty. A fast-forward that fails is divergence: report it and route to `/gitlore:resolve`.
7. **Propagate the tiers.** For each mounted tier: initialize, fetch its remote `live` fast-forward-only, and re-detach at `live`. A diverged, unfetchable or mid-merge tier is reported by name and left untouched — never silently skipped, because a tier that stops propagating looks exactly like one with nothing to say.
8. **Compose the indexes**, then run the dangling-pointer report (D17). A refusal writes nothing and says why; a partial write says which indexes are composed.
9. **Emit the standing orientation** on `additionalContext`: the FR11 prohibition (D12) and the active tiers' own routing descriptions (D17).

**Worktree creation — handled by `SessionStart`, not a `WorktreeCreate` hook**

Memory-worktree setup for a new worktree happens lazily at the next `SessionStart` in that worktree (`git -C <main-repo>/.git/modules/gitlore-memory worktree add --detach <worktree-path>/<memory-rel-path> live`). This is uniform across every way a worktree comes into being:

- **`claude --worktree <name>`** — starts a *new session* in the new worktree, so `SessionStart` fires there with `cwd` = the worktree path (verified, CC 2.1.150).
- **Manual `git worktree add`** — next `SessionStart` in that worktree handles it.
- **Claude Desktop's worktree button** — does not fire `WorktreeCreate` at all (CC #57209), but a session still starts there, so `SessionStart` covers it.

Lazy creation is correct: with no session there is no auto-memory being written, so there is nothing to set up until the first session needs it.

**Prerequisite — the hook wrappers must be gitlink-aware (D11).** Memory-worktree creation at SessionStart is only *reachable* in a linked worktree once the wrapper paths are anchored in the git common dir. With the original literal `.git/gitlore-*` paths, `emit-wrappers` (step 3) aborted SessionStart under `set -e` *before* this step ran, and committing in the worktree was blocked outright. The common-dir anchor (D11) is what makes the `SessionStart`-covers-everything claim above actually hold for linked worktrees; without it, "a session still starts there" was necessary but not sufficient.

> **Why not a `WorktreeCreate` hook.** Verified against CC 2.1.150 (`claude-code-guide`, 2026-05-25): `WorktreeCreate` is an **override** hook — it fires *before* the worktree exists, the script is expected to *create* it and print only its absolute path on stdout, and any extra stdout makes CC hang (#27467). Its stdin carries `{hook_event_name, cwd, name}` — **no** worktree path and **no** branch (CC defaults the branch to `worktree-<name>`). It also does not fire for Desktop-created worktrees, and there is no post-creation hook (#27744). Registering it would mean hijacking worktree placement for zero benefit over the `SessionStart` path. The earlier assumption that command hooks receive `worktree_path`/`worktree_branch` on stdin was wrong for `WorktreeCreate`; `hookSpecificOutput.worktreePath` is an HTTP-hooks-only *output* field and irrelevant here.

**`WorktreeRemove`** (advisory — cannot block)

Input provides `worktree_path` only (verified CC 2.1.150 — no branch field). Advisory: a non-zero exit logs a warning but cannot stop the removal.

Guard: no-op if `.gitmodules` has no `gitlore-memory` entry.

1. Derive the memory submodule worktree path as `<worktree_path>/<memory-rel-path>`. If it is not a registered memory worktree (e.g. no session ever ran there, or an ephemeral subagent worktree), no-op. Otherwise `git -C <memory-gitdir> worktree remove <memory-submodule-worktree-path>` (prune if the directory is already gone). On failure (locked, uncommitted changes), emit a warning; never block parent worktree removal.
2. Nothing else is removed. CC leaves the parent branch in place on worktree removal (verified 2.1.150, #28422, #38287), and memory carries no named branch of its own; `live` is shared and survives. Gitlore never touches parent branches.

**`PostToolUse(Bash)` — the commit nudge.** `post-tool-use.sh` watches for the project's own pre-commit check, configured as `gitlore.precommitCommand` and matched by command prefix. It fires when that command exited 0, memory is dirty, and the commit-message file is absent or stale (mtime against the newest memory file — a content hash is not worth the complexity; an edit that rewrites identical content re-triggers, which is acceptable noise). On trigger it emits `additionalContext` asking Claude to summarize the pending memory changes, present the summary, and write it to the commit-message file **only** after explicit user approval. That ordering is FR11's gate: the file must not exist until approval exists.

The nudge fires once per dirty episode. A `gitlore-nudged` marker in the store's gitdir suppresses a repeat while memory is still dirty and unapproved, and `gitlore_sync_memory_to_live` clears it once memory is committed. The marker lives in the gitdir because the hook can write git internals and the agent cannot — nothing to gitignore.

**`PostToolUse(EnterWorktree|ExitWorktree)` — the drift guard.** `worktree-drift.sh` warns when an in-process worktree switch has moved the session's cwd away from the repo whose memory is redirected. See D15.

**`PreToolUse(Write|Edit|Bash)` + `PostToolBatch` — the index pair.** `index-sync-pre.sh` stamps the root index and the tier manifest before a watched call; at batch end `index-sync-post.sh` mirrors changed index hooks into frontmatter and `index-compose.sh` recomposes if either stamp moved. Keying on what changed rather than on what the call declared is what covers a `sed -i` under `Bash`, which names no path at all. See D17.

**`PostToolBatch` — the file-triggered actions.** Three hooks act on an intent file the agent wrote as an ordinary edit: `memory-commit-batch.sh` (standalone memory commit), `add-tier-batch.sh` (mount or create a tier) and `recall-batch.sh` (fetch memory bodies). The shape is deliberate and shared: the agent writes a file, a hook does the git — sidestepping both the command sandbox and the auto-mode classifier, neither of which lets the agent do this work itself.

The standalone commit is the `handoff` plugin's path, not the general one (D16). The agent writes the approved summary (`.claude/gitlore-memory-message`) and the trigger (`.claude/gitlore-commit-memory`); `memory-commit-batch.sh` runs `commit-memory.sh -F <msgfile>`, which commits with the blessed sentinel and advances local `live` without a parent commit. The trigger is deliberately kept out of the general agent-facing instructions — the SessionStart orientation, the nudge, and the gate's block message all describe only the message-file plus parent-commit path — so an agent not running the handoff skill is never taught it can force a standalone memory commit.

**Both IPC files are removed only on a complete commit.** A locked repo and an in-flight merge are expected transients, so on any failure the trigger *and* the message file stay put and the next batch retries — no agent action, no lost approval. A trigger with no approved summary is likewise kept, so the commit completes on its own the moment the summary lands.

**`SessionStart` and `PreCompact` — the recall reset.** `recall-reset.sh` clears the recall ledger. Both events end the context the ledger describes; see D18.

#### Git Hooks

Both hooks run in the parent repo's chain, and both begin the same way: capture `GIT_INDEX_FILE` and any replay state, then clear git's full local-env-var set (`git rev-parse --local-env-vars`). Git exports those variables scoped to the *parent*, and a `git -C <submodule>` that inherits them breaks submodule resolution or, in a linked worktree, silently redirects the submodule's refs and objects into the parent's store. Both exit 0 when the repo has no `gitlore-memory` entry, and when the submodule worktree is absent (a session-less linked worktree) — never block a parent git operation over memory.

**`pre-commit`** commits memory and moves the pointer, in this order:

1. **Stand down during a replay.** A rebase, cherry-pick or revert re-creates commits authored earlier while the memory worktree stays put, so syncing would re-pin a historical commit to today's memory. Detected via `--git-path rebase-merge|rebase-apply|CHERRY_PICK_HEAD|REVERT_HEAD` before the env unset (replay state is per-worktree), announced rather than skipped silently. `MERGE_HEAD` is excluded: a merge commit is authored now and must pin current memory.
2. **Refuse to proceed over a stale merge state** (abort-then-retry, or manual intervention when `MERGE_HEAD` is already gone).
3. **Sync every dirty tier** and advance each tier's local `live`, so the gitlink the memory commit is about to record has already moved (D17).
4. **Sync memory** through the shared `gitlore_sync_memory_to_live`: the FR11 dirty/freshness gate, `add -A`, `GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>`, remove the message file, then `push . HEAD:live` fast-forward-only. Divergence prepares a merge and yields (`gitlore_yield_merge`), exiting 1.
5. **Stage the gitlink** into the index git handed the hook — the captured `GIT_INDEX_FILE`, restored for that one `git add`, because a bare `add` misses the `-a` and pathspec index flavors and dies on `index.lock` under them.

Every refusal branches on `$CLAUDECODE`: agent-facing text naming the next action, user-facing text directing them to open the project in Claude Code.

**`pre-push`** publishes in the same before-and-alongside order: each tier's `live` to its own remote, then memory's. Failure is fatal — a tier that silently stops publishing is indistinguishable from one with nothing to say. The memory-absent skip stays non-blocking but warns when the gitlink about to be published is not reachable on the memory remote, decided locally without a fetch. Divergence routes to `/gitlore:resolve`, which diagnoses the flavor.

#### Memory Commit Entry Point

**`commit-memory.sh`** — a callable script (not a git hook) that commits the memory submodule and advances local `live` **without a parent commit**, so a skill can satisfy the FR11 gate at an interactive moment and a later non-interactive parent commit never trips it. See D16.

Arg-driven, `git commit`-style: `-m <summary>`, `-F <file>`, or `-F -` (stdin/heredoc). It resolves the memory path, writes the summary to the commit-msg file, then calls the shared `gitlore_sync_memory_to_live`. Guards (exit 0): not a gitlore repo / no `gitlore-memory` submodule / submodule worktree absent / memory clean-and-synced. Dirty with no summary supplied → exit 1 with a caller-facing message.

**Discovery.** A `gitlore.commitCommand` git config key resolves to `$PLUGIN_ROOT/scripts/commit-memory.sh`, re-pinned every `SessionStart` (self-healing across plugin-cache path changes, like `gitlore.hooksDir`, D5) and seeded at install in `write-settings.sh`. A caller finds the script with one `git config gitlore.commitCommand` lookup — no coupling to gitlore's internal layout.

**Shared body.** `gitlore_sync_memory_to_live` (lib) is the commit-and-advance-live logic factored out of `pre-commit`: dirty/freshness gate → `add -A` → `GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>` → `rm <msgfile>` → `push . HEAD:live` (ff) → divergence (prepare / write merge-state / emit directive / exit 1). Both `pre-commit` and `commit-memory.sh` call it — one implementation, no drift.

#### Memory Push Entry Point

**`push-memory.sh`** — the sibling of `commit-memory.sh` on the publish side: it pushes each tier's `live` and then memory's to their own remotes **without a parent push**, so an agent or skill can satisfy FR8 at a moment when no parent commit is in flight. See D20.

Takes no arguments — there is nothing to approve, because FR11 gated this content when it was committed and publishing an already-approved commit adds no disclosure decision. Guards (exit 0): not a gitlore repo / no `gitlore-memory` submodule / memory worktree absent. Exit 1 carries a message on stderr naming the next action, including a prepared merge routed to `/gitlore:resolve` when a remote has diverged.

On success it reports what moved, per store — commits published and where `origin/live` now sits — from remote-tracking refs captured before the push. Uncommitted changes are named as **not** published rather than left to be assumed so: a push publishes commits, and the one wrong inference available to someone who just asked to publish is that dirty work went with it.

**Discovery.** `gitlore.pushCommand`, seeded at install and re-pinned every `SessionStart`, exactly as `gitlore.commitCommand` is (D5, D16).

**Shared body.** `gitlore_push_stores` (lib) is the tier-then-memory publish logic factored out of `pre-push`: memory's stale-merge guard → remote-configured check → per tier (checkout guard, `live` guard, remote check, stale-merge guard, fetch, ff push, divergence → yield) → memory fetch → memory push → unreachable-vs-refused discrimination → divergence yield. Both `pre-push` and `push-memory.sh` call it, so the tier-before-memory ordering that FR8 rests on cannot drift between them; `pre-push` keeps only what is its own, the session-less-worktree warning about an unpublished gitlink.

### Hook Manager Support

Detection script outputs structured results. Each hook manager has an idempotent wiring step (uses marker comment `# gitlore: managed` to detect and skip duplicates) and a sentinel command stored in `.claude/gitlore-hook-setup` and replayed by SessionStart on clone or plugin reinstall.

**Detection precedence** (first match wins; multiple detections produce a warning listing all found managers):

1. `.lefthook.yml` or `lefthook.yml` → Lefthook
2. `.husky/` directory → Husky (v7+)
3. `.overcommit.yml` or `.git/hooks/overcommit-hook` → Overcommit
4. Otherwise → None (direct)

The `direct` case is the default whenever no recognized manager is present — whether the repo has a hand-rolled `.git/hooks/pre-commit` (the direct installer appends, coexisting) or no hooks at all. The shared `.git/hooks` dir exists in every git repo, so direct wiring always works; defaulting bare repos to it means the double-commit guarantee (FR8) is active out of the box rather than waiting on a manual copy-paste step. `manual` is **no longer auto-detected** — it remains a valid sentinel a user can set by hand, and is still emitted for the ambiguous multi-manager case (multiple managers found → gitlore can't choose → manual instructions).

**Wiring** is applied symmetrically for `pre-commit` and `pre-push`. Every manager reaches the wrapper through `$(git rev-parse --git-common-dir)/gitlore-<hook>` rather than a literal path (D11), so what differs per manager is only how that command is spelled and whether a shell expands it.

*Lefthook* (`lefthook install`) — a `gitlore` command under `pre-commit` and `pre-push` in `lefthook.yml`, `run: '$(git rev-parse --git-common-dir)/gitlore-pre-commit'`. Lefthook runs `run` through a shell, so the substitution expands at hook time.

*Husky* (`npx husky`) — a guarded `exec "$(git rev-parse --git-common-dir)/gitlore-<hook>" "$@"` appended to `.husky/pre-commit` and `.husky/pre-push`, created if missing. Husky runs the script via `sh`, so the substitution expands.

*Overcommit* (`overcommit --install`) — a custom `gitlore` hook under `PreCommit` and `PrePush` in `.overcommit.yml`. Overcommit's `command:` is an array exec'd **directly, with no shell**, so the wrapper has to be reached through an explicit one: `command: ['sh','-c','exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"','gitlore']` — the trailing `'gitlore'` sets `$0`, and overcommit appends the applicable files as `$@`.

*None, i.e. direct* (sentinel `direct`, a keyword SessionStart interprets rather than runs) — shell stubs at `git rev-parse --git-path hooks/<hook>` that exec the wrapper. The hooks path is resolved with `--git-path`, not a literal `.git/hooks/…`, so the `[ -f ]` test and the `cat >` survive a sentinel replay in a linked worktree.

*Multiple managers, or a hand-set sentinel* (`manual`, also a keyword) — print a copy-paste snippet and modify nothing. Reached only when detection is ambiguous or a user sets the sentinel themselves.

**Sentinel handling in SessionStart:**

- `direct` → re-run the direct-wiring installer.
- `manual` → emit `systemWarning` reminding the user to verify wiring.
- Any other value → run as a shell command in the repo root.

Idempotency: every wiring modification uses a detection marker (`# gitlore: managed` or the format-appropriate equivalent). Re-applying is a no-op.

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

Most divergence is detected while the agent is attempting commit or push. The agent sees the hook's exit-1 stderr (addressed to it via the `$CLAUDECODE` branch) and invokes `/gitlore:resolve` inline without user intervention.

1. Agent invokes `/gitlore:resolve` after observing a hook failure.
2. Script fetches `origin`, detects divergence flavor(s).
3. For each flavor (head-vs-live, then head-vs-remote), script runs the same plumbing against the matching authority and dispatches a sub-agent for semantic synthesis.
4. Sub-agent reads changed files, synthesizes holistically; asks the parent via SendMessage if anything needs clarification.
5. Parent agent approves the synthesis summary with the user; sub-agent commits.
6. Script advances `live` (and, for a remote-flavored merge, `origin/live`), leaving HEAD detached at the new `live`.
7. Parent context refreshed with incoming diff (or user directed to `/clear` if resolve ran at session start).
8. Agent retries the original commit or push.

**Resolve fallback: user-driven**

If divergence surfaces outside a Claude session (`git commit` or `git push` run from a plain terminal), the hook's stderr directs the user to open this project in Claude Code and run `/gitlore:resolve`. The primary path resumes from there.

**Clone**

`git clone --recurse-submodules <repo>` → the first `SessionStart` configures settings, detaches memory at `live`, and replays the hook-manager sentinel.

Without `--recurse-submodules`: `SessionStart` detects the uninitialized submodule and runs `git submodule update --init`. That leaves the memory submodule at a **detached HEAD** on the recorded gitlink SHA with only the remote-tracking `origin/live` — no local branches. Since the branch-model logic references `live` as a *local* ref (checkout source and ff-merge target), `SessionStart` first materializes a local `live` from `origin/live` (falling back to the checked-out `HEAD` when memory has no remote), then proceeds as above. Without it the first post-clone session dies on `fatal: 'live' is not a commit`.

**Worktree creation** — `SessionStart` in the new worktree initializes the memory submodule worktree, detached at `live`. Uniform across `claude --worktree`, manual `git worktree add`, and the Desktop button (all start a session in the worktree). See "Worktree creation — handled by `SessionStart`" above for why no `WorktreeCreate` hook is used.

### Remote Repository

The memory submodule is pushed to a dedicated remote, matching the parent repo's provider, ownership, and visibility where possible.

**Naming**

- Default: `<parent-remote-name>-memory`, derived from `origin` on the parent (e.g., `github.com/org/project.git` → `project-memory`).
- If a repo with the default name exists in the target namespace, prompt for an alternative.

**Ownership**

- Default: same owner as parent `origin` (user account or org).
- Overridable at creation time.

**Visibility**

- Default: match parent repo (public parent → public memory; private parent → private).
- Rationale: memory is auxiliary to the project; no reason to split access control.
- User can override the default.

**Install-time disclosure (informational)**

Before creating the remote, display proposed name, owner, and visibility (inherited from parent), along with:

> Memory pushed to this remote may contain any context Claude has recorded — project details, decisions, or incidental session content. Each memory commit is reviewed and confirmed before it's pushed, so you control what goes up.

This is orientation, not a clearance gate. The effective gate is the per-commit review (FR 11).

**Creation method**

1. **GitHub + `gh` CLI available** → `gh repo create <owner>/<name> [--public|--private]` matching parent visibility.
2. **Other providers** → emit copy-paste instructions: "Create a repository at `<detected-provider>` named `<name>` with matching visibility, then paste the clone URL here." Wait for URL.
3. **Parent has no remote** → skip memory remote creation. Memory stays local-only. Informational message; user can add a remote later.

**On creation failure** (auth, quota, network, name collision): fall back to method 2 (copy-paste). Do not abort install.

**Push semantics**

Per NFR5 (double-commit semantics): memory `live` is pushed before parent push on every `git push`. Parent remote always points at a submodule SHA reachable on the memory remote.

---

## Design Decisions

**D1 — `live` branch as memory trunk, independent of parent's default branch**

Using the parent's default branch name (`main`, `master`, `develop`, …) as the memory trunk would put every session on the branch they all merge into, and would tie memory's ref layout to a name each project chooses for its own reasons. `live` is a dedicated trunk no session ever works on, which makes the merge target unambiguous in every store — memory and tiers alike.

**D2 — Per-worktree named branches by default; detached HEAD when parent is detached**

**Superseded by D17's detached-at-`live` branch model:** no store carries a named working branch. Recorded here for the argument that was weighed and lost — merge commits from a detached HEAD reference their source by commit id rather than branch name, which reads worse in `git log`. That readability cost is real and was accepted, because named branches collide in a tier's shared gitdir and buy no branch-scoped history.

**D3 — Ordinary checkout during resolve, not git plumbing**

`git commit-tree` + `git update-ref` were designed to avoid checking `live` out in a linked worktree, and rejected: standard porcelain is easier to reason about than low-level plumbing, and the merge has to leave a conflicted worktree for the resolver to read anyway.

The resolve merge originally acquired `live` with `git checkout live`, which doubled as a write lock — git's one-checkout-per-branch rule made a concurrent resolve fail fast. Under D17's detached model the prepare uses `checkout --detach <authority>` instead, so there is no lock and no contention to fail on: any number of worktrees can sit on the same commit.

**D4 — Commit message via file handshake**

Claude writes a commit message file at the parent working tree's `.claude/gitlore-memory-message`; the commit hook reads, uses, and deletes it. Path is resolved via `git -C <memory-path> rev-parse --show-superproject-working-tree`, then `/.claude/gitlore-memory-message`. It sits in the parent working tree rather than the memory submodule's gitdir so the agent can write it — the gitdir is write-blocked by the CC sandbox and the auto-mode classifier.

Write timing: the file is created only after the user explicitly approves the commit summary Claude has presented. The file's presence is the signal that a memory commit has user approval; absence or staleness blocks pre-commit.

Alternatives rejected:

- **Stop hook:** fires on every response turn, not only before commits — unnecessary writes and churn, and no clean trigger for the confirmation prompt.
- **Force-write on memory edit:** PostToolUse on every `Write`/`Edit` would generate noise and couple commit preparation to individual edits rather than commit intent. The chosen trigger (PostToolUse on the configured pre-commit command) is a stronger signal of intent with cleaner timing.
- **`claude --print`:** no session context, cannot ask user for confirmation, no memory of why edits were made.

**D5 — Wrapper scripts in the git common dir, not tracked**

Tracking hook scripts in the repo would cause commit churn on every plugin update and couple the repo's history to the plugin's versioning. Storing flat wrappers in the git common dir (`<common-dir>/gitlore-pre-commit`, `<common-dir>/gitlore-pre-push`, resolved via `git rev-parse --git-common-dir`) keeps them untracked and local. `SessionStart` regenerates them on every startup, so they always reflect the current plugin version. The common dir (rather than a literal `.git/`) is what makes the wrappers reachable from linked worktrees, where `.git` is a gitlink file — see Hook wrappers above and **D11**.

Wrappers exec the real hook scripts via `$(git config gitlore.hooksDir)/<hook>`. The wrapper degrades to a clean skip (exit 0 + stderr hint) in **two** cases, not one:

1. **`gitlore.hooksDir` unset** — a plain `git commit` outside any Claude session before SessionStart has fired. Hint: install the marketplace, plugin, and start Claude.
2. **`gitlore.hooksDir` set but `$HOOKS_DIR/<hook>` does not exist** — the version-pinned config points at a plugin-cache dir that was GC'd after a plugin upgrade, in the window before the next SessionStart re-pins it. Without this guard the wrapper `exec`s a missing path and the commit/push **hard-fails** with `exec: …: not found`. Hint: start Claude Code in this repo to refresh the hooks dir.

Both keep git operations unblocked rather than breaking a commit on a transient/stale-config condition.

**D11 — Gitlink-aware wrapper paths (common-dir anchor) for linked-worktree support**

The original design hardcoded the relative path `.git/gitlore-<hook>` in the wrapper writer (`emit-wrappers`) and in every hook-manager consumer. This works only when `.git` is a directory — i.e. only in the main worktree. In a linked worktree `.git` is a gitlink *file*, so the path fails on both sides: `emit-wrappers`' `cat > .git/gitlore-*` aborts SessionStart under `set -e`, and the shared wired hook (which lives in the common dir and therefore fires in *every* worktree) `exec`s the literal `.git/gitlore-*` and **blocks the commit** (`exec: … not found`). Both were verified empirically against git 2.47.3.

Resolution: anchor the wrapper at `$(git rev-parse --git-common-dir)/gitlore-<hook>` on both the write and exec sides, across all managers (direct, husky, lefthook, overcommit, manual). The common dir is shared, so one emission covers every worktree, including a session-less linked worktree (plain `git worktree add` + `git commit`).

Considered and rejected: a **per-worktree** anchor via `git rev-parse --git-path gitlore-<hook>` (which resolves to `…/worktrees/<name>/gitlore-<hook>`). It reintroduces the commit-blocking gap in any worktree where no session has run yet, because the shared wired stub would `exec` a per-worktree wrapper that does not exist. The common-dir anchor has no such gap. (The commit-message file legitimately uses the per-worktree `--git-path` because each worktree has its own pending message; the wrapper is the opposite — one shared executable.)

Corollary fix: once the wrapper *fires* in a linked worktree, the git-hook runs `git -C "$mempath" …` under `set -e`. If the memory submodule worktree was never created there (session-less worktree), this would abort and block the commit for a *new* reason. Both `pre-commit` and `pre-push` therefore guard with an early `[ -e "$mempath/.git" ] || exit 0` — nothing to sync, never block.

**D6 — Merge direction: more-authoritative side is first parent**

Across all resolve flavors, the merge commit records the more authoritative side as first parent; the divergent side becomes the second parent. This preserves the conventional `git log --first-parent` reading — the authoritative trunk stays linear, divergent work appears as merged-in contributors.

- **head-vs-live** (post-commit): local `live` is the trunk; the pending commit on the detached HEAD is the divergent side. First parent is `live`, second is the pending commit.
- **head-vs-remote** (pre-push): `origin/live` is more authoritative than anything local. First parent is `origin/live`, second is the pending commit (which by then carries local `live`).

Reversing either direction would make the authoritative side look like a branch of the divergent side, breaking the `git log --first-parent` convention.

**How the direction is achieved under the detached-at-`live` model (D17).** Both flavors run the same two steps: pin the pending commit at `refs/gitlore/pending`, then `checkout --detach <authority>` and merge the pending commit in. Detaching *at the authority* is what puts it first; because no branch is ever checked out, this cannot collide with another worktree (the concurrent-checkout failure the old `checkout live` had). The pin exists because nothing else references the pending commit once `merge --abort` drops `MERGE_HEAD` — under the retired model a named branch held it.

**D7 — Scripts decide, agent handles language**

Detection and branching logic (hook-manager type, remote provider, merge state, divergence flavor) lives in shell scripts that output structured results. The agent handles language-level work: summarizing memory changes, synthesizing merged memory content, communicating with the user, and answering clarification questions for sub-agents.

Benefits:

- **Deterministic and testable:** scripts can be unit-tested; model behavior can't.
- **Auditable:** git plumbing is visible in code, not hidden behind natural-language reasoning.
- **Stable across model versions:** logic that must not drift doesn't rely on the model.

Load-bearing for `/gitlore:resolve`: the script determines divergence flavor, selects plumbing sequences, and dispatches the sub-agent with a scoped context. The agent never decides which git commands to run.

**D8 — Remote creation requires explicit user confirmation**

Creating a remote repository is a visible external action with side effects outside the local machine (namespace occupancy, provider-side records, potentially public visibility). Even when `gh` CLI is available and parameters are straightforward, the agent presents the full proposal — name, owner, visibility, creation method — and waits for explicit approval before executing.

This confirmation is distinct from the install-time disclosure, which is informational orientation. D8 gates the specific external action. Rationale: external actions are not covered by the per-commit review gate and require their own opt-in.

**D9 — Sub-agent for merge synthesis (requires experimental flag)**

`/gitlore:resolve` dispatches a sub-agent with fresh context for merge synthesis. The parent session's in-memory context reflects the pre-merge state of files; after `git merge --no-commit --no-ff` rewrites them on disk, the parent's assumptions are stale. A sub-agent reads the post-merge state freshly, avoiding stale-context writes.

The sub-agent + SendMessage pattern requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Install checks for the flag and offers to enable it. Known limitations (no session-resumption for in-process teammates, task-status lag) are documented; they do not affect the gitlore use case, which runs the sub-agent within a single live session.

When the flag stabilizes or the feature becomes default, the install-time check becomes a no-op. No other design changes needed.

**D10 — Memory redirect via a launch-time `--settings` shim, not project settings**

Claude Code resolves `autoMemoryDirectory` only from the `policySettings`, `flagSettings`, and `userSettings` tiers (verified by reading the resolver in the CC binary, v2.1.150). Project-level `.claude/settings.json` and `.claude/settings.local.json` are deliberately excluded for security — a checked-in repo setting must not be able to redirect where a user's memory is written. The discard is silent: a project tier carrying the key produces no diagnostic, and memory simply lands in the default `~/.claude/projects/<sanitized-cwd>/memory/` dir (Rejected Alternatives).

The honored tiers are either global (`userSettings`, `policySettings`) or per-launch (`flagSettings`, via `--settings`). Per-project redirection without polluting other projects therefore requires supplying the value at launch. A thin `claude` shim injects `--settings '{"autoMemoryDirectory":…}'` transparently (see Memory Redirect Launcher). This keeps the value proposition intact — the user invokes Claude Code normally and uses its *native* auto-memory; only the storage directory is redirected, with no cowork semantics.

Because an unredirected launch strands memory silently, the `SessionStart` launcher guard (sentinel `GITLORE_LAUNCHED`) detects one and warns.

**D12 — Submodule-side commit gate (defense in depth for FR11)**

A gate on the **parent** side alone leaves FR11 open on one flank. The parent `pre-commit` hook reads the magic commit-message file and, finding memory clean (or no fresh summary), commits or blocks — but the memory submodule is itself an ordinary git repo, so a commit made *directly inside it* (`git -C <mempath> commit`, a human `cd <mempath> && git commit`, a script) meets nothing: no summary, no approval, no handshake. Dogfooding on a downstream project hit exactly that — an agent recorded the submodule directly, then committed the parent over an already-clean submodule.

Two complementary mechanisms close it:

- **Hard gate (load-bearing).** A `pre-commit` hook *inside* the memory submodule, emitted by `emit-memory-gate.sh` into `git -C <mempath> rev-parse --git-path hooks/pre-commit` (the shared common hooks dir, so one emission also covers linked-worktree memory trees — D11 parity). It admits a commit **only** when the env sentinel `GITLORE_MEMORY_COMMIT=1` is present, and blocks otherwise with a `$CLAUDECODE`-branched message. Every gitlore-internal commit path exports the sentinel: the parent `pre-commit` blessed commit, both `/gitlore:resolve` merge commits, and the install initial commit. A naked commit by an agent, human, or script never sets it. This makes FR11 a shell-enforced invariant (NFR1 "no AI on hot path"; D7 "scripts decide") on *every* commit path, not just the parent route.

  An env sentinel — not "fresh magic file present" — because resolve's merge commits use git's `MERGE_MSG`, not the magic file, so a file-presence gate would block legitimate resolve commits. One sentinel covers all three blessed paths uniformly.

  The wrapper mirrors the parent wrappers (D5): it resolves the live plugin via `git config gitlore.hooksDir` and degrades to a clean `exit 0` + hint when that key is unset or stale. Because the gate fires under the *submodule's* git context — where `git config` reads the submodule config, not the parent's where SessionStart pins the key — `emit-memory-gate.sh` mirrors the parent's `gitlore.hooksDir` into the submodule config (common config, shared across submodule worktrees). The graceful-degradation window (plugin cache GC'd before the next SessionStart re-pins) admits an unguarded commit, accepted for NFR8 parity with the parent wrappers; the next SessionStart re-wires it.

- **Orientation (removes the friction of hitting the hard gate).** `SessionStart` emits a standing `additionalContext` every gitlore session carrying the **prohibition** — memory is a gitlore-guarded submodule; never commit inside it directly — plus the one-line seamless happy path (writing a memory file is an ordinary edit; committing the *parent* repo is all you need, and its pre-commit hook records, gates, and pushes memory). The base Claude Code memory instructions describe generic "edit files, save facts" memory with no review gate, so the agent's default is actively wrong in a gitlore repo; the prohibition corrects the model **before** the agent acts, making the hard gate a safety net rather than the everyday teacher. The prohibition *must* be front-loaded: it guards an action the agent would otherwise take unprompted, so nothing downstream would trigger its disclosure in time. The four-step persist *procedure* (summarize → approval → write the magic file → commit the parent) is deliberately **not** preloaded — front-loading a recipe reads as "a process you must run" and induces ceremony (pausing for user approval before even writing a memory file) when persistence is meant to be seamless. That procedure is surfaced just-in-time instead: by the `memory-pre-commit` hook's own `$CLAUDECODE`-branched output when a direct commit is actually blocked, and by `/gitlore:resolve` on divergence — at the moment the action happens, not resident all session.

This is a cleaner variant of the rejected PreToolUse alternative — a submodule hook consistent with the existing hook architecture, with none of the CC-level scoping complexity.

**D13 — Lock-contention retry wrapper for mutating memory git calls**

SessionStart, `pre-commit`, `pre-push`, and `/gitlore:resolve` all run `git -C <mempath> …` against the memory submodule. Concurrent Claude sessions (or a session racing its own background work) can collide on the index/ref lock, and a transient `index.lock` / `cannot lock ref` failure would abort the operation — blocking a commit or stranding SessionStart under `set -e`. The fix is `gitlore_git` (`scripts/lib/util.sh`), a drop-in wrapper that retries `git "$@"` on transient lock contention with exponential backoff. The default schedule (`0.1 0.2 0.4 0.8 1.6 3.2 3.7`) sums to exactly 10.0s wall-clock — the last term is the budget remainder, not a doubled value — and is overridable via `GITLORE_GIT_RETRY_SCHEDULE` (tests set it to zeros for instant runs).

Only lock-contention failures retry, recognized by `gitlore_git_is_lock_error` matching `index.lock`, `file exists`, `unable to create …*.lock`, `cannot lock ref`, and `another git process`. Every other failure fails fast — retrying a real error wastes the budget. The `is already used by worktree at` message is explicitly **not** retryable: that is D3's one-checkout-per-branch write lock signalling that another session holds the resolve lock, a deliberate fast-fail, not transient contention. The final attempt's stderr and exit code surface unchanged and stdout passes through untouched, so the wrapper is transparent to callers. Applied to mutating calls only (`branch`, `checkout`, `merge`); read-only probes never take the lock and stay on plain `git`.

**D14 — User-facing SessionStart output on `systemMessage`**

The Claude Code hook output channels (characterized 2026-06-10): `systemMessage` (top-level JSON field) is the only reliably user-visible channel; `hookSpecificOutput.additionalContext` is injected into the model's context but **never echoed to the user**; stdout is consumed as JSON and not echoed; stderr is shown to the user only on exit code **2** (or any non-zero under `--verbose`). SessionStart is non-blocking — the session continues regardless of exit code.

A notice on stderr is therefore effectively invisible, and a silent success path leaves the user with no confirmation that memory is wired at all. Routing notices through the agent (`additionalContext` "tell the user…") is rejected: it puts the model on the hot path against NFR1/D7.

Every user-facing SessionStart notice rides `systemMessage`, accumulated into the single SessionStart JSON the hook writes to fd 3:

- **Divergence** error → `systemMessage` + `exit 0`. Exit 0 because the channel is proven to work on exit 0 (the launcher guard rides it) and unverified on exit 1, because SessionStart's exit code is non-blocking and consumed by nothing, and because stdout JSON is parsed only on exit 0 — a non-zero exit would discard the very message it was meant to signal. The script still halts there, before the tier propagation pass.
- **Dirty-skip** notice → `systemMessage`, informational.
- **Clean success** → a brief confirmation (`memory ready (detached at live)`), per the chosen always-confirm behaviour.
- **Launcher-not-redirected** warning → `systemMessage`; when present it leads the message and the state line follows.

`additionalContext` carries the standing commit-protocol orientation (D12) on every path. The agent-vs-user text branch (`gitlore_say_for_agent_or_user`) exists only for the git hooks (`pre-commit` / `pre-push` / `memory-pre-commit`), which run outside a session where `CLAUDECODE` may be unset; SessionStart always runs in-session, so its notices are written directly for the user.

**D15 — In-process-worktree memory-drift guard**

Claude Code's in-process `EnterWorktree` moves the session cwd into a linked worktree but **freezes the launch environment** — `PATH`, `autoMemoryDirectory`, and `CLAUDE_PROJECT_DIR` all stay pinned to the repo the session launched in (verified by transcript capture, 2026-06-09). The memory-redirect shim (D10) injects `autoMemoryDirectory` once at launch, so after an in-process `EnterWorktree` the agent edits files in the worktree while CC's auto-memory keeps writing to the **launch** repo's submodule. Memory silently strands in the wrong working copy — the cwd-vs-launch divergence is the drift signal.

A `PostToolUse` hook on the targeted matcher `EnterWorktree|ExitWorktree` (`scripts/cc-hooks/worktree-drift.sh`) catches the transition and emits one user-visible `systemMessage` (D14's substrate) when the session has drifted. The targeted matcher rests on an empirical confirmation (2026-06-10, this repo) that `EnterWorktree` **does** fire `PostToolUse` and that a name-based matcher matches `tool_name`. It beats a `"*"` matcher with a fast bail: it fires exactly once per transition — zero per-tool cost, and no de-dup state, because it cannot fire on the intervening `Bash` calls.

Drift predicate (all read-only git, bail silently on any error): the current worktree's `--show-toplevel` differs from the launch root's, **and** both resolve to one shared `--git-common-dir` (a linked worktree of the *same* repo, not an unrelated directory). `ExitWorktree` restores cwd to the launch root, so the predicate is false and the hook is silent — the Enter-warns/Exit-silent asymmetry is intentional. The guard also requires the launch repo to be a gitlore-enabled repo with a registered memory submodule; otherwise there is no redirected memory to strand. No shim change is needed — the guard reads the frozen `CLAUDE_PROJECT_DIR` (already relied on by the `version-guard` hook) and compares it to the moved cwd.

**D16 — Standalone memory-commit entry point (arg-driven)**

The only blessed path to commit memory is committing the parent repo, which fires `pre-commit` (sentinel commit + advance `live`). That is wrong for a caller that wants to commit *only* memory at an interactive moment so a later non-interactive commit never trips the FR11 gate: the parent commit drags whatever else is staged (handoff has already `git add -f`'d its task file), and a naked submodule commit is blocked by the D12 gate. The motivating caller is `/commit-commands:commit`, which forbids prompting; splitting review from commit otherwise causes drift or redundant reviews. So an interactive caller (`handoff`) couples review+commit once, up front, through a standalone entry point.

The entry point is `scripts/commit-memory.sh`: it commits the dirty memory submodule with the `GITLORE_MEMORY_COMMIT=1` sentinel and advances local `live` (`push . HEAD:live`) — no parent commit. Origin push stays with `pre-push`. The commit-and-advance-live body it shares with `pre-commit` is factored into one lib function, `gitlore_sync_memory_to_live`; both callers invoke it, so the intricate divergence tail has a single implementation.

**Arg-driven, not file-driven.** The script takes the approved summary as an argument (`-m`, `-F <file>`, `-F -`), mirroring `git commit`, and writes it to the commit-msg file itself. The message file stays purely the hook↔commit IPC handshake (D4) rather than becoming the caller's contract, which keeps callers from reconstructing gitlore-internal paths. The freshness gate stays *inside* the shared body because `pre-commit` still needs it to refuse un-approved commits; on the script's path it is satisfied by construction (the summary is written immediately before the commit, so the mtime check always passes). The per-commit FR11 approval therefore rests on the *caller's* contract here — the interactive caller obtains explicit user approval before invoking — while the mtime gate continues to protect the non-interactive parent path. A blessed interactive entry point trusting its caller's approval is the intended split, not a hole.

**Discovery via `gitlore.commitCommand`.** Re-pinned to `$PLUGIN_ROOT/scripts/commit-memory.sh` every `SessionStart` (the self-healing re-pin that absorbs plugin-cache path changes, exactly as `gitlore.hooksDir` does, D5) and seeded at install in `write-settings.sh`. Existing repos pick the key up on their next session — no reinstall. The key is a *path pin, not an activation signal*: a caller decides whether gitlore manages memory here from the `gitlore-memory` submodule registration in `.gitmodules` (FR12 — the same gate `pre-commit` uses, never stale), not from the presence of the key. The key only answers *where* the script is, and is trustworthy because `SessionStart` refreshed it this session; a caller should still verify the resolved path is executable and degrade with a "restart your session" hint rather than exec a missing path (the D5-extension staleness window). Graceful no-op (exit 0) mirrors the hook guards: not a gitlore repo / no `gitlore-memory` submodule / submodule worktree absent / memory clean-and-synced; dirty with no summary supplied refuses with a caller-facing message. Caller wiring is out of scope for the gitlore side: `handoff` consumes the key in its own work; `/commit-commands:commit` stays untouched until there is a second real caller.

**D17 — Mechanism for tiered memory (FR15): nested global/org submodules + structural index composition**

FR15 calls for shared tiers (a truly-global `lore`, an org-scoped `ddaanet`, …) surfacing in *every* participating repo alongside its local memory, without a flat merge that would blow the always-loaded index budget. Motivation: across N sibling repos, `user`, CC-platform `reference`, and portable `feedback` facts duplicate and drift, while `project` facts are correctly repo-local. The mechanism:

*Empirical grounding (retrieval instrumentation, 2026-07-14; full evidence trail in `docs/references/cc-memory-retrieval.md`).* CC auto-recall was characterized in both `--print` and a real interactive (tmux PTY) session against a scratch `autoMemoryDirectory`:

- Only the **root `MEMORY.md`** is always-loaded; a nested `team/MEMORY.md` is **not** auto-loaded.
- Bodies are **not** bulk-loaded. Recall is a **tool-gated `Read`** of a selected file (surfaced interactively as "Recalled 1 memory"; an auto-issued, empty-thinking Read in the transcript), steered by the root index. Disable file tools → no body, in both modes.
- A file listed in the root index recalls reliably (100% in probes); an unindexed/subdir-only file relies on the agent grepping to discover it (~75%).
- **Both** the root one-liner **and** the per-file frontmatter `description` feed CC's selection classifier — each an independent lever (U1) — but only the always-loaded index line is *reliably* recall-reachable.

Consequence: a tier's facts become reliably recall-reachable **iff their pointers appear in the root `MEMORY.md`**, regardless of where the bodies physically live. The design keeps Anthropic's memory structure (index + files + agentic recall) and upgrades only gitlore's *composition* of the root index.

**Two surfaces, bidirectional drift — the index line is canonical.** A memory file carries its pointer text twice: the root `MEMORY.md` one-liner and the frontmatter `description`. These **drift apart bidirectionally** — the agent only ever has the root index loaded, so it revises whichever surface it is looking at and the other goes stale, in *both* directions (evidence, from a git-history audit of this repo's own memory: `feedback_memory_retrieval_in_practice` kept a fresh index line over stale frontmatter; `reference_git_hook_env_leak` was the reverse — corrected frontmatter/body, stale index line). Neither surface is a reliable single source of truth, and judging which of two divergent texts is fresher is a *semantic* call, not a string op. So the **root index one-liner is treated as canonical** — agent-curated, always-loaded, and the reliable retrieval lever; the frontmatter `description` is a secondary, weaker match-surface. **No mechanism derives the index text from frontmatter** — deriving it would clobber curated lines and re-inject stale text (Rejected Alternatives).

**Materialization — nested submodules, discovered by enclosure.** Each tier is a git submodule mounted *inside* the project's memory submodule at a free-form path (`memory/ddaanet`, …). It reuses the existing init, FR11 commit gate, and push-lockstep machinery — a submodule-within-a-submodule, more nesting of an already-solved problem (D11/D12 carry the linked-worktree and hook-env scar tissue). Discovery is by **enclosure, not name**, and the asymmetry with the parent level is load-bearing: the parent picks *one* submodule out of possibly many by the fixed name `gitlore-memory` (the `GITLORE_SUBMODULE_NAME` constant, resolved to a path through `.gitmodules`), so a repo's unrelated submodules stay foreign; but a submodule nested *inside the memory store* is a tier *by definition* — `SessionStart` enumerates the memory submodule's own `memory/.gitmodules` and treats every entry as a tier. No tier-name constant exists, nor should one: at the memory level the enclosure is the signal, which is why "don't hardcode the tier name" falls out for free. The first concrete tier is org-scoped `ddaanet`; a truly-global tier waits until there is anyone to share it with.

**Routing — the agent picks the directory; no content classifier.** Which tier a new fact belongs to is a *generation* choice the authoring agent owns, guided by the standing SessionStart `additionalContext` (the D12 orientation block): portable facts → the appropriate `memory/<tier>/`, project facts → `memory/`. The directory *is* the tier *is* the submodule, so the FR11 gate commits whichever submodule the file landed in — no shell logic inspects a fact's content to route it. This is consistent with D7 ("scripts decide"): that principle governs *detection/mechanics*, and where to file a fact you are already authoring is not detection. **The per-tier routing guidance is self-describing and travels:** each tier states what it is for in its own `memory/<tier>/MEMORY.md` frontmatter `description:` — authored once by whoever owns the tier and identical in every consuming repo, the DRY that a per-consumer routing manifest would break — and `SessionStart` reports the descriptions of the *active* tiers (see the manifest below) into `additionalContext`. Composition only ever moves `- […]` pointer lines, so this frontmatter is never spliced; a clean separation between "what the tier is for" (frontmatter, intrinsic, travels) and "which tiers are active here and in what order" (the manifest, local). (The routing guidance rides `additionalContext` — model-only per D14, and observed not to inject under `--print` — so a missed guidance misfiles a global fact into the project tier: self-correctable, never corruption.)

**Index composition is placement, never text-derivation and never hygiene.** The composition owns a *tier* line's presence and placement *in the root index*, never its text and never the project's own lines. It reconciles two surfaces per active tier by **line identity = path prefix** — no sentinel text is ever injected into either index: a root-index pointer whose path begins with an active tier's mount dir (`ddaanet/…`) is that tier's line; a bare path (`project_overview.md`) is a local/project line. Reconciliation is bidirectional with a **prefix rewrite** — *splice up* each carrier line into the root index prefix-added (`- [T](foo.md)` in `memory/ddaanet/MEMORY.md` → `- [T](ddaanet/foo.md)` in the root, so the always-loaded Read resolves to `memory/ddaanet/foo.md`), and *mirror down* each root tier line into the carrier prefix-stripped, so a locally-authored line travels with the tier submodule into every consuming repo. The composed root index is `[tier blocks, in manifest order] → [project lines]`: tier blocks ordered by the manifest, each preserving its carrier's own line order; project bare-path lines last, in the order CC arranged them (composition never reorders or touches them). It is **idempotent** — an already-canonical index rewrites to identical bytes, so no spurious churn. The carrier is *not* consulted by CC for recall (only the root is always-loaded); it exists purely as the tier's canonical, travelling store, and composition is what surfaces it in the always-loaded index. Deactivating a tier (removing it from the manifest) drops its block from the root on the next compose; the lines persist in the carrier. The agent — and CC's native pointer-writing — owns each line's *text* and its creation and deletion; composition only relocates tier blocks. Root `MEMORY.md` writers are therefore disjoint by *aspect*: the agent owns text and per-file presence, the composition owns tier-block placement.

**The tier manifest — activation and precedence, never inferred from bare presence.** Composition, routing-advertising, and ordering are all keyed on one consumer-local file, `memory/.gitlore-tiers` (tracked in the memory submodule, one tier path per line, top = highest precedence). It is the single **activation** surface: *listed = active*. A tier can be mounted (its submodule present) yet **inactive** (absent from the manifest) — a first-class, harmless state. The manifest gates three things uniformly: only listed tiers splice into the root index, only listed tiers are advertised for routing, and their listing order is their precedence. Ordering lives here rather than in `.gitmodules` (whose section order is incidental add-order, rewritten by git porcelain) or in the index (which CC rewrites freely and must carry no marker text) — an explicit, git-porcelain-untouched container, consumer-local because precedence is a per-repo choice (repo X may rank `ddaanet` above a future tier Y, repo Z the reverse). With a single tier ordering is trivial (tier, then project lines); the manifest is what makes it *free-form* for N tiers, and a `project` interleaving token is a cheap future extension (default: project last). The manifest is **never populated from `SessionStart`'s passive discovery-by-enclosure** — enumerating whatever submodules happen to exist under `memory/` must not imply activation, since a stray or manually-mounted submodule could exist for unrelated reasons, and a half-formed one (still mid-creation, before it self-describes) must stay invisible to composition. `/gitlore:add-tier` is a different case, not passive: it only runs because the agent explicitly named *this exact tier* to mount or create, so the ambiguity discovery guards against does not arise, and it activates as its own last mechanical step (appended at the bottom — lowest precedence, the least surprising default). Reordering, or listing a tier mounted by hand, stays a deliberate manual edit to the file.

**Compose triggers and validation.** Composition runs at three points. At `SessionStart`, after the tier fast-forward, to surface propagated lines. Mid-session on **`PostToolBatch` when the root index or `memory/.gitlore-tiers` is written** — the magic-file trigger that lets the agent edit the manifest, see the regenerated index, and adjust ordering within one session (SessionStart-only composition is ruled out by this story). That mid-session trigger keys on **what changed, not on what the batch declared**: `index-sync-pre.sh` stamps the root index and the manifest before the call, and `index-compose.sh` composes at batch end if either stamp moved. A tool call is a poor proxy for a change in both directions — an `Edit` can rewrite a line to itself, and a `sed -i` under `Bash` never names its target at all, which is why the `PreToolUse` matcher is `Write|Edit|Bash` and a Bash call takes the baseline unconditionally. Detecting the change is what covers a `sed`-applied index edit, which would otherwise land with neither propagation nor composition running. This trigger has two paths to the same `gitlore_compose_and_report` call: the stamp comparison above, and `/gitlore:add-tier`'s own activation write, which happens inside `add-tier.sh` after the baseline was taken and so cannot be attributed to a tool call — `add-tier-batch.sh` calls the same function directly, in the same batch, right after a successful mount. Composition itself doesn't care which path fired it. And in the **merge continuation, before it commits**: a merge synthesizes an index outside any tool edit, so it is the one write path into a store that the other two triggers cannot see, and composing there puts the composed bytes in the merge commit itself rather than in a later, unrelated one. That pass is **up-only** — see the Rejected Alternatives for why mirroring down during a merge is wrong. The recompose **validates and is fail-safe**: it refuses — reporting on `systemMessage` (user) + `additionalContext` (agent) without clobbering the existing index — if the result would carry a **duplicate** pointer line, or if the manifest **lists a tier that is not present** (a stale or mistyped entry). A mounted tier *absent* from the manifest is not an error, only inactive (the asymmetry is deliberate: listed-but-absent = broken; present-but-unlisted = dormant). In the continuation that refusal is reported but never blocks: compose writes nothing when it refuses, and by then the merge is synthesized and approved — stranding it half-landed over an index problem the agent fixes in one edit is the worse outcome, so the merge commits uncomposed and says so. Composition spans the whole memory tree, so from the continuation it can also write a store *other* than the one being committed — the root index when a tier merged, a carrier when memory did. Those writes stay dirty and ride the next FR11 commit, the same float the `SessionStart` recompose produces.

**The `Bash` arm is measured, not assumed**. Watching `Bash` widens the `PreToolUse` matcher from calls that name a memory file to every shell call, so the trade was settled against this machine's own transcript corpus — 2,441 transcripts, 22,168 `Bash` calls, 13 months. Of those, ~49 mutated a real memory store: ~22 touched an index, ~29 a fact file (the sets overlap; some calls do both). Fifteen were `git checkout`/`git restore` and three `git rm` — write paths that name no `file_path` at all, so no `Write|Edit` matcher can see them however it is scoped, which is the part of the case that cannot be met another way. The comparison volume is 1,190 `Write`/`Edit` calls on memory files, so the arm exists for roughly 4% of the mutations and ~0.2% of the `Bash` calls it inspects. Two distribution facts sharpen it. All but one of the 49 fall in the last five weeks — the behaviour is recent and rising, not a long-tail artifact. And of 25 native auto-memory stores under `~/.claude/projects/*/memory`, exactly one was ever mutated from `Bash` across the whole corpus: shell mutation is a *gitlore*-store phenomenon, because a gitlore store is a git repo the agent already runs git against. Cost, timed against this repo's real tree (23 KB index, one tier, 30–50 runs per path, steady state): **~45 ms** on a `Bash` call once the batch has a baseline, **~65 ms** on the first watched call of a batch (two `cksum`s plus the index `cp`), against ~18 ms for the bare unwatched-tool exit; a cold page cache roughly doubles all three. That is ~45 ms added to every shell call to catch a mutation in one call out of five hundred. Accepted: the failure it prevents is silent — the edit lands, neither propagation nor composition runs, and the store desyncs with nothing to show for it — and 45 ms is invisible next to a tool call's own latency.

**Add and create — two scenarios, one converges into the other, both activate as their own last step.** **Mount** (common — a repo joins an existing tier): `git submodule add <url> memory/<name>`. **Create** (rare — the first repo stands up `ddaanet`): init an empty module, seed its `MEMORY.md` + frontmatter `description:`, create and push its remote, *then* take the identical mount path — the gap between "module exists" and "module self-describes" is real during the seed step, but nothing outside the script can observe it, since both modes converge before either commits to the manifest. `/gitlore:add-tier` performs the mount, with a `mode=create` path for the creation flow; rarely used, but a real command beats hand-editing files by README directions. The command routes its git through the same trigger-file pattern as the FR11 commit path — the agent writes `.claude/gitlore-add-tier` (`key=value` lines: `mode`, `name`, `url`, `description`) and a `PostToolBatch` hook runs `scripts/add-tier.sh` on its behalf. Two independent reasons the agent cannot run it itself: the auto-mode classifier reads a submodule mutation as self-modification, **and** mounting clones while the agent's command sandbox has no network — a hook runs outside both. The intent is one-shot (consumed whether it succeeds or fails), because an add-tier failure is a bad url or a taken name, not a transient lock worth retrying. Because the hook has network and no sandbox, the url is bounded to a scheme allowlist before git sees it — the `helper::address` transport form (`ext::`, which runs a shell command) is refused outright rather than left to git's `protocol.ext.allow` default.

Both modes end by **appending `name` to `memory/.gitlore-tiers`** as their final mechanical step — activating the tier at the bottom of the file, the lowest precedence, the position that cannot outrank a tier this repo already trusts, and reorderable by hand afterwards. (The manifest paragraph above covers why an explicitly named mount may activate where passive discovery may not.) Neither mode commits inside memory: `gitlore_tier_paths` reads `memory/.gitmodules` from the working tree, so a staged `submodule add` is already discoverable and the FR11 gate stays the sole committer — the manifest write is the same kind of working-tree-only edit. Because the manifest write happens inside a hook, after `index-compose.sh`'s pre-batch baseline was taken, it cannot be attributed to a tool call; `add-tier-batch.sh` calls the shared `gitlore_compose_and_report` helper directly on a successful mount, folding the recompose (and, since the active-tier set just changed, the post-mount triage nudge) into the one JSON response it emits, then drops the compose stamp so the same manifest change is not reported twice in one batch.

**The index is authoritative over a pointer line's presence, and nothing is deleted to enforce it**. The index is what memory *contains*: a file on disk with no pointer line is not part of memory, and a line is added or removed only by the agent, deliberately. Authority here is a reading rule, not a licence to make one surface match the other — in particular, removing a line never deletes the file it named. A destructive edit as the silent consequence of an index edit is exactly the surprise a memory store must not spring, and the file is the only place the fact still lives. Composition may *report* a mismatch; it never repairs one.

*This settles coverage, prune, and dedup — all three stay out.* **Coverage** (reconstruct a missing pointer line from a file's frontmatter) contradicts the rule outright: an unlisted file is unlisted on purpose, and seeding a line would resurrect one the user removed. **Prune** (delete a bullet whose file is gone) inverts the rule, letting the file set decide presence; under index authority the line is the record and the *missing file* is the anomaly, so dropping the line silently destroys what may be the last recoverable trace of a lost memory. Both also hardcode a semantic call — was this deletion deliberate? — that belongs to the agent. (This is about *file presence* never driving a line's deletion. It is orthogonal to how a *tier* line's presence is reconciled between the root and carrier indexes, which the three-way compose below settles by diffing index states against a base — never by consulting a file.) **Dedup** falls on independent grounds: it guarded duplicate path lines from a `merge=union` driver that is not used (see Conflicts below), and distinct per-index namespaces make cross-index duplication impossible, so it guards nothing anywhere in the system.

What the rule *does* leave open is a non-destructive **dangling-pointer report** — a fifth compose validation naming any bullet whose target file is absent, alongside the four already there. It reports and does not refuse: unlike the existing four, a dangling line does not make the composed output wrong, and refusing the pass would block every later write over a stale line the agent can fix in one edit. Because it reports rather than refuses, it is a *separate pass* (`gitlore_compose_dangling`) that every compose trigger calls after `gitlore_compose` returns, not a rule inside `gitlore_compose_check` — the check's contract is "refuse and write nothing", and compose's own return value stays a list of what it *wrote*. It runs on the composed store and speaks whether or not anything was written, so a stale line surfaces on the next index edit even when composition was already idempotent. It scans each mounted tier's carrier as well as the root: a **dormant** tier's bullets never reach the root, so a root-only scan would leave them unchecked for as long as the tier sleeps. A line present in both indexes resolves to one file and is reported once, against the root — the surface the agent has loaded and edits.

**Root↔carrier composition is a path-keyed three-way merge**. The root's tier block and the carrier are two projections of the same facts, and either can change between passes — the agent edits the root (adds or removes a bullet), a propagation-in fast-forward changes the carrier (upstream added or deleted a fact). From two snapshots alone a line present in one but not the other is ambiguous: did that side add it, or did the other side delete it? Only a **base** disambiguates. So compose merges per path — keyed on the pointer path, not the line text, so a line whose only difference is a curated *hook* resolves by rule (the root's text wins, the canonical-index decision) rather than false-conflicting. A path present at base survives only if **both** sides still carry it (a delete on either side wins); a path new since base survives if **either** side added it (an add on either side wins). Adds and deletes then propagate in both directions — including the agent deleting a tier fact by removing its root bullet — and file presence is never consulted.

The base is the carrier **as of the last compose**, and `refs/gitlore/compose-base` in the tier is the **audit chain** that holds it: one commit per pass that reconciled something, each recording *both* merge inputs as `carrier.md` (the base the next pass merges against) and `root.md` (the root index it agreed with), parented on the previous. The base is therefore `refs/gitlore/compose-base:carrier.md`, and `git -C <tier> log refs/gitlore/compose-base` is the history of what every past pass merged. It tracks composes, not commits, on purpose: the design lets root composition *float* behind a commit (a fast-forward leaves `memory/` dirty and rides the next parent commit; a carrier edit can be committed before root is projected), so the committed gitlink runs ahead of what root reflects and would read a not-yet-projected add as a delete — dropping it. The chain grows only when root and carrier are actually reconciled: a pass whose tree matches the tip appends nothing, so the log records what moved rather than how often the hook fired. Before the first compose there is no ref and the base is empty — a union, since nothing existed to have been deleted.

Recording the root side is what makes a lost pointer diagnosable at all. Both inputs are needed to replay a merge, and the root is the one that cannot be recovered afterwards: it floats ahead of any commit, so the state a pass actually read may never have been committed anywhere. A ref naming a bare **blob** is the pre-log shape; that blob *is* the carrier, so it is still read as the base and the next save migrates the ref to a chain with a parentless first commit. The chain is local by construction — `refs/gitlore/compose-base` is outside `refs/heads`, so nothing pushes it — which is correct for an audit of what *this* clone composed.

**Order is a merge input, not a rule applied afterwards**. Where a bullet sits in an index is an authored choice — the agent groups related facts, puts the ones it wants seen first at the top — so both the root↔carrier compose and the divergence merge merge the *order* as well as the presence, through `gitlore_order_merge`: git's own three-way over the three **path sequences**, with `--union` resolving a shared offset to ours-then-theirs and the first occurrence of a repeated path winning. Each side's placements are honoured, so an insertion keeps the offset its author gave it instead of being appended to the block. Only a genuine disagreement about one offset falls back to the rule, and it is never surfaced as a conflict: two sides inserting *different* facts at one point disagree about placement, not about content, and there is nothing for a human to adjudicate. The sequences are **paths only, never bullet text** — feeding the lines in would make every reworded hook a positional edit, so a routine description change would relocate its entry and false-conflict against an unrelated insertion beside it. Compose takes the root as ours (the root index is the surface the agent edits) and the carrier as theirs, so root ordering propagates down and splice-up reproduces it; a fact that arrived in the carrier from another consumer keeps that consumer's offset, because the compose-base makes its arrival a positional insertion rather than an append. Ordering authority stops at the tier block: composition still hoists each active tier's block above the project's own lines, in manifest order.

**Authoring-time sync is one-way (index → frontmatter), because the index is canonical.** A separate `PreToolUse(Write|Edit|Bash)` + `PostToolBatch` pair on the root `MEMORY.md` mirrors an edited index one-liner's hook into the target file's frontmatter `description` (after-the-dash hook → `description` only; never `name`/title, which is the `[[wikilink]]` slug and file identity). The direction is deliberately one-way: a *bidirectional* sync would resolve conflicts by tool-call order (last writer wins), and since the file body is usually written after the index, the weaker frontmatter would propagate *back* and clobber the curated index hook — the reliable retrieval lever. The store makes this concrete: index hooks routinely carry content the frontmatter lacks (`feedback_memory_before_root_commit` adds "never leave it dirty or ahead"; `reference_cc_worktree_memory_freeze` adds "Enter/Exit confirmed to fire PostToolUse"), so letting frontmatter win a conflict is a silent downgrade. `PreToolUse` captures the pre-edit index image so the post half acts **per line, keyed by what changed against that image** — not a blanket sweep, which would push an unrelated *stale* index line onto fresh frontmatter (the `reference_git_hook_env_leak` direction). A line whose **hook changed** propagates, overwriting the `description`; a **newly-added** line (absent from the pre-image) fills the `description` *only when it is empty*, never clobbering a description authored alongside the new file in the same batch (fill-if-empty); an **unchanged or merely reordered** line is a no-op. The post half runs on **`PostToolBatch`**, not `PostToolUse`: it fires once per tool batch carrying every call in `.tool_calls[]`, so a batch holding several index edits syncs and reports once rather than per edit. A batch is one assistant message's worth of calls, not a user turn — a single turn fires it as many times as the agent takes batches (observed 2026-07-27), which is why every baseline below is per-batch. It does not read those calls, though — the stash the pre half left is the whole signal. Its presence says a watched call ran this batch, and `cmp` against the file on disk says whether that call moved anything; a `Bash` call, which announces no path, is covered by exactly the same comparison. The baseline is correspondingly per-*batch*: the first watched call of a batch stashes, later ones must not re-stash (that would diff against a mid-batch state and lose the earlier edits' changes), and the post-hook drops the stash at every batch end — even one where the index went untouched — so a pre-image can never become a *second* batch's baseline. A stash stranded by an interrupted batch is consumed rather than discarded: the difference between it and the file is a propagation still owed, deferred rather than dropped. `PreToolBatch` would pair more neatly but is unverified: absent from the hooks reference, and unlike `PostToolBatch` (proven in the wild by the shell-scripting plugin's shellcheck hook) nothing observed confirms it fires for a single call. A frontmatter-only edit is left untouched; this hook never writes the index. It deploys globally through the plugin hooks (no per-project work). It is **complementary to, not a substitute for, the structural recompose**: the sync sees only in-session tool edits, so propagation (tier lines arriving via `SessionStart` ff, merges, or `/gitlore:resolve`) is invisible to it — precisely what the structural pass covers.

**Both hooks are non-blocking but never silent**. Neither may ever `exit 2` — the one code that blocks, and only at `PreToolUse`; at `PostToolUse` nothing can block because the tool has already run. But `exit 0` is not licence to swallow errors: a genuine failure (the stash `cp` fails; a frontmatter write fails) reports on `systemMessage`, the D14 channel. Here `exit 0` is *required for visibility rather than merely tolerated*, because **stdout JSON is parsed only on exit 0** — a non-zero exit would discard the `systemMessage` and make the error *less* visible, not more (this is why D14 moved SessionStart's errors off `stderr`+`exit 1` in the first place). The post-hook therefore checks each `gitlore_set_frontmatter_description` explicitly (an `if !` condition, which suspends `errexit`) so one bad target cannot abort the loop and strand the rest, and consumes the stash **unconditionally** — a surviving pre-image is a hazard, since a later silently-failed `cp` would leave the next post-hook diffing a fresh index against an ancient baseline and propagating wrong hooks. `|| true` and a bare `|| exit 0` on a fallible command are rejected as dishonest error paths.

**A routine sync reports on both channels, asymmetrically**. Propagation overwrites an authored `description:` — the agent writes considered prose and the canonical index hook replaces it — so the pass has to say so rather than discard it silently. The two audiences want opposite volumes. The **user** gets one line (`gitlore: reset frontmatter to match MEMORY.md (N files)`) plus `suppressOutput` — the sync is routine and the before/after is noise; only a *failure* names its file, because only a failure needs action. The **agent** gets the full `old → new` list on `additionalContext`, plus the standing direction that the rewrite is complete (do not re-read to verify) and that a hook losing meaning is fixed **in the index line, not the file** — at the explicitness required for compliance, every clause earns its place.

**The same pass carries two routing-key advisories**. The sync copies the index hook over the file's own `description:`, so both of CC's match surfaces come from that one line — and a hook with nothing in it to match on degrades both at once, silently. Two things about a line are countable, and both **report and never refuse**, the asymmetry the dangling-pointer report settled: `PostToolBatch` cannot undo the write, and a thin hook is a quality regression rather than corruption.

The first is the **byte budget**. The index blob is loaded verbatim into every session, so cost is bytes, not lines, and the longest entries are where curation pays — measured here, the five longest lines are ~a fifth of the whole blob while every terse behavioural line together is a rounding error. Past `GITLORE_INDEX_BUDGET_WARN_PCT` (80) of `GITLORE_INDEX_BUDGET_BYTES` (25600) the pass names the percentage and the five largest lines. It is arithmetic, so it has no false positives.

The second flags a line **carrying no trigger token** — no path, flag, error string, identifier, filename or version of the kind a future query would contain. It is conditioned on the memory's `type`: a `reference` fact is reached by the surface where you meet it, while a `feedback` rule is reached by topic and is right to be prose. That gate is what makes it usable — measured over this repo's 76 bullets, ungated it fires on 22, type-conditioned it fires on **3 of 37** eligible lines, and all three are the ones worth rewriting. Detection is word-at-a-time in awk rather than one ERE, because ERE word boundaries are not portable (GNU `\b` vs BSD `[[:<:]]`) and splitting on whitespace makes the boundary safe by construction — so `well-known` stays prose while `--flag` is a flag. Both advisories are **diff-keyed like the sync itself**: only lines this batch added or changed are examined, or an old thin hook would re-report on every unrelated index edit. The token check deliberately runs *before* the fill-if-empty bail, since a line whose frontmatter the sync declines to touch is still the canonical routing key.

What neither can see is the third failure mode — a trigger that is *present but buried* in a paragraph-length line. That is a semantic judgement, left to the agent. A tf-idf-style score over the store's own bodies cannot supply it either (Rejected Alternatives).

**One-time reconcile — the semantic complement the one-way sync can't cover.** The sync only pushes a *freshly edited* index line onto frontmatter; it never fixes a **stale index** line (the harmful direction — `reference_git_hook_env_leak`: fresh frontmatter/body, rotted index), because judging which of two divergent texts is fresher is a *semantic* call, not a string op. Pre-existing drift therefore needs a one-time reconcile that picks the correct one-liner per divergent file and writes it to the canonical index (frontmatter then follows on that edit). It runs **after the sync is deployed** — reconciling first, then editing without the sync in place, just re-drifts frontmatter and wastes part of the sweep. It is **per-project** (each repo's store carries its own accrued drift) plus **once per shared tier**. Since the sync deploys everywhere automatically but the reconcile is a per-project cost that scales, it is **opportunistic, not mandated**: an explicit sweep (optionally a `/gitlore:reconcile` command, dogfooded here first) is worth running only where a stale **index** line actually bites — the index is the reliable lever; stale frontmatter is low-harm and heals on that line's next index edit. Non-gitlore CC-memory stores are out of scope (no gitlore hooks, no sync). **The reconcile re-verifies against current reality rather than propagating body→index.** Measured here (2026-07-17): of 60 index lines only 4 were genuinely stale, and *two of those had stale bodies as well* (an `.envrc`-vars claim the platform had since changed; a `--print`-suppresses-hooks claim a direct test refuted). "Index stale ⇒ trust the body" is therefore unsafe — bodies rot too, especially platform- and behaviour-dependent ones. The correct one-liner comes from re-verifying the claim against reality and then writing it to the index; a wrong *body* is fixed, along with any downstream code or docs it seeded, not propagated. At that scale no `/gitlore:reconcile` command is warranted — 4 files is a manual sweep.

*Distinct from the rejected "PostToolUse on every memory Write/Edit" (Rejected Alternatives).* That entry rejects PostToolUse as a trigger for **commit preparation** (couples commit intent to individual edits; noisy). D17's PostToolUse does **structural index composition** (tier-block placement — never text derivation) — cheap, idempotent, no commit semantics — an orthogonal use of the same event.

**Branch model — detached at `live`, one commit path.** Both the memory submodule and every tier are checked out **detached at `live`'s commit**, not on a named working branch. `live` is the sole persistent, travelling ref; a detached HEAD is the per-worktree checkout. Detached HEADs coexist on one commit, which is what a tier needs — its gitdir is shared across a repo's memory worktrees, where named branches would collide (per-parent-branch branches are in Rejected Alternatives). Durability rests on `live` alone: the commit path advances it immediately, so `live` holds every commit the moment it exists. The payoff is **one commit path**: a merge always reduces to "my pending commit vs the authoritative `live` (local, then remote)", every resolution re-detaches at the new `live`, and the `branch-vs-live` / `local-vs-remote` split collapses along with the per-worktree checkout dance.

**Tier commit/push lockstep — driver-side, one approval per episode.** A tier commit rides the same before-and-alongside staircase the parent already applies to memory, one level deeper: `gitlore_sync_tiers_to_live` commits every dirty tier and advances its local `live` *before* memory's own `git add -A`, so the moved gitlink is part of the memory commit rather than lagging it; `pre-push` pushes each tier's `live` to its own remote *before* memory's, so the pointer never goes out ahead of what it points at. Two decisions the shared driver rests on:

*One approval summary per memory episode, not per tier.* The gate is keyed to a single message file, and the episode's approved summary is reused verbatim as the commit message in every store it touched. The user approves a set of *writes*, not a set of repositories; N prompts for one decision buys no extra information. What the approval prompt owes the user is **grouping by destination** — a line bound for a shared tier is more public than one bound for project memory, and that difference is the only part of the split that carried real content.

*No recursing `pre-commit`/`pre-push` in the memory store.* Recursion is driver-side, exactly as the parent already drives memory: the parent's hooks call the sync function and push explicitly rather than relying on a hook one level down. A hook-side version would re-litigate the full `--local-env-vars` unset and the `GIT_INDEX_FILE` capture/restore at a level that needs neither, and would force the FR11 gate to share `memory-pre-commit` with the driver — the gate exits 0 on its first line under the blessed sentinel, so the two would diverge by sentinel inside one hook. `memory-pre-commit` stays a pure gate and is now *emitted into each tier as well*, since neither the parent's hooks nor memory's own gate reach a submodule-inside-a-submodule; each tier gets its own `gitlore.hooksDir` mirror because the wrapper's `git config` reads whichever store it fires in.

Scope is every **mounted** tier, not only the active ones: the manifest governs routing and composition, and silently dropping a dormant tier's writes would be data loss rather than dormancy. Each loop guards `[ -e "$tierpath/.git" ]` before any `git -C` — into an unchecked-out submodule that escapes to the enclosing repo, which would have committed *memory* under the tier's name and pushed memory's `live` to the tier's remote. Tier divergence surfaces at both gates — the pending commit against the tier's local `live` (`head-vs-live`) and local `live` against the tier's own remote (`head-vs-remote`) — is reported by tier name with git's own reason, and resolves through the same merge path as memory: each gate yields to `gitlore_yield_merge`, the state file names the store the merge was prepared in, and the continuation finds it by walking the stores (Workflows).

**Propagation + pinning.** SessionStart fast-forwards the nested tier submodule(s) so a global fact authored in another repo arrives; the recomposition that follows leaves `memory/` **dirty — expected**, and it rides the *next* parent commit like any other memory change. No scheduled sync-commit and no FR11 churn: the pin floats, committing naturally with the next parent commit rather than on a schedule of its own, which keeps the reused submodule model intact.

**Conflicts on shared tiers.** Two repos inserting into a tier's `MEMORY.md` concurrently are resolved the same way as any memory divergence — the semantic memory-merger sub-agent, which merges both insertions without duplicating them. A `merge=union` driver is deliberately *not* used: it concatenates blindly and would leave duplicate pointer lines needing a cleanup pass. And because each index occupies a distinct filename namespace — the root holds bare project paths, each tier carrier only that tier's filenames — composed blocks never share a path across indexes either. So no duplicate-pointer residue arises on any path and no dedup pass is needed. No append-only constraint is imposed; conflicts are expected rare (the more global a tier, the more stable it presumably is).

**Memory files merge as prose with a base section; index files merge as entries.** `gitlore_prepare_merge` runs git's own three-way with `merge.conflictStyle=diff3`, so every conflict the sub-agent reads carries the `|||||||` base — which side *changed* a line is unknowable from two versions alone, and that is precisely the judgement a semantic merge asks for. Index files then go through a second, entry-wise pass (`scripts/lib/index-merge.sh`), because an index is a list of records keyed by pointer path and a line-wise merge reads it as prose. That misreading fails in both directions: two sides inserting **different** facts at the same offset conflict textually although nothing is in dispute, and two sides inserting the **same path** at different offsets do not conflict at all and yield a duplicate pointer — the state `gitlore_compose_check` refuses on, so the silent textual success is what strands the store. The entry-wise pass keys on the path and applies D17's presence rule (at base → survives iff both keep it; new since base → survives if either adds it), resolves text against the base, and emits a diff3 chunk only for a path both sides moved apart. It runs on **every** index in the merge, not only the ones git flagged, since the duplicate arises from a merge git considers clean; a side that already names one path twice is *declined* rather than collapsed, leaving the malformed index for `gitlore_compose_check` to report. Because the pass resolves an index in the worktree without staging it, `conflicted_files` in the state file is the union of git's unmerged entries and `gitlore_conflicted_indexes`. Its chunks carry **git's own labels** — `HEAD` for the authoritative side (checked out detached by the prepare) and the incoming commit's sha — rather than a vocabulary of gitlore's own, so one merge never presents the sub-agent with two namings of the same two sides. Aligning the labels is one argument at the call site; the alternative is a sentence in `agents/memory-merger.md` reconciling the two, and a configuration that removes the need for agent-facing prose beats the prose.

**The merger sub-agent is briefed with both side diffs and the tree.** Alongside the state file, `gitlore_prepare_merge` writes three read-only artifacts into the store's gitdir — `gitlore-merge-mine.diff` (base→authority), `gitlore-merge-theirs.diff` (base→pending) and `gitlore-merge-tree` (`ls-files`) — named in the state file as `mine_diff`, `theirs_diff` and `tree`. The merged worktree shows the outcome but not the intent, and re-deriving the intent is work the sub-agent would otherwise do with git commands it should not be running. `gitlore_clear_merge_state` is the single remover for the state file and all three, so a briefing cannot outlive its merge and be read against the next one. **`No conflict.` is an explicit valid answer** for the sub-agent: divergence is a git fact, not a semantic one, and a merge whose two sides say compatible things is the common case. It is a finding to check, not an admission that the work was skipped — the agent still reads both diffs and the changed files, still runs `git add -A`, and still stops for approval.

---

**D18 — Active recall: a request file the hook serves, not a gate the agent must pass**

CC's native recall runs a per-query classifier against the **user prompt**, returns at most five files it is certain about, and is instructed not to re-select within a conversation. A fact whose trigger only appears *mid-task* — a git rejection string, a `2>/dev/null` in a file just opened, an empty `$TMPDIR` — therefore has no path into context. Closing that gap is FR16.

**The hook reads; it cannot make the agent read.** No hook output field can inject a `tool_use` or force a `Read` — verified against the shipped binary (2.1.217), where `injectToolCall`/`requestTool`/`forceRead`/`forceToolUse` have zero occurrences while `additionalContext` has 180. That is not a limitation to work around: having the hook read the named files and emit their contents as `additionalContext` is *better* than a forced Read — one round trip instead of two, no tool-permission surface, and the selection lands in a file that can be validated and logged. The same "agent writes a file, hook does the work" shape as the memory commit trigger (D16), for the same reasons.

**Skill, not a gate.** The obligation lives in a skill rather than in a global `PreToolUse` deny (Rejected Alternatives). `skills/recall/SKILL.md` is invoked by the user, by the agent when it notices a trigger, or — the load-bearing case — by another skill at a checkpoint it prescribes — a calling skill's flow is deterministic where a global gate is indiscriminate. This makes the *fetch* deterministic and the *selection* auditable; it does not make invocation mandatory, and that is the accepted trade.

**Cap 5, hard failure.** The same number as CC's own classifier. Over the cap reads *nothing* and asks the agent to reassess: a list of nine means the selection was never made, and silently keeping the first five would hide exactly that. `no match` is a first-class answer — the checkpoint exists to force a decision, not to manufacture a lookup. A rejected request is consumed like an accepted one, because retaining it would re-report the same problem on every later batch; with no gate blocking the agent, re-requesting is free.

**The ledger, and why it clears at `PreCompact`.** `recall-batch.sh` records every `Read` of a file under the memory store, which catches CC's *own* recall too — "Recalled 1 memory" is a real `Read` tool call in `.tool_calls[]` — so active recall never re-injects a body the native classifier already pulled. Records are `<hash> <relpath>`: content-addressed, so a memory edited since it was read stops counting as known. The ledger is only valid while the context is, and a compaction ends that — what survives is a summary, not the tool results, and re-injection after `/compact` is guaranteed only for the project-root `CLAUDE.md`. Which reads the summarizer kept is unknowable, so the whole ledger is dropped: re-fetching a body still present costs tokens, while assuming presence that is gone withholds a fact the agent believes it holds. Only the first error is recoverable. `SessionStart` clears it too — `--resume` keeps the session id but not the context.

**Index as routing table.** The premise the skill rests on: an index line carries the *trigger keywords* so read-or-skip can be decided from it, not the fact itself. Always-on directives were moved out of `MEMORY.md` to `CLAUDE.md` and path-scoped `.claude/rules/`, whose `paths:` frontmatter fires on reading a matching file — native harness support for the same mid-task-trigger problem, along the file-path dimension.

---

**D19 — Memory-approval wording: one canonical clause, discovered externally via a git-config key**

The FR11 approval prompt — "summarize pending memory changes, present as a blockquote, get approval" — is needed at four call sites: three inside gitlore (`post-tool-use.sh`, `memory-commit-batch.sh`, `resolve.sh`'s `gitlore_sync_memory_to_live`) and a fourth in the `handoff` plugin's `checkpoint_memory_directive`, a caller in the D16 sense that drives its own memory commit around gitlore's IPC files. Composed independently, they drift — the three internal ones did once (2026-07-16, "one prompt fix, three surfaces"), and a hand-synced copy in a different repo entirely can only drift further.

**The wording is a self-contained block, appended last.** `reference/memory-approval-clause.txt` holds the body spec — subject line, blank line, then **one paragraph per changed memory file**, each opening `**<Kind> <tier>/<slug>:**` with the kind drawn from New, Update, Augment, Reduce, or Remove — followed by a literal template of three example paragraphs. A `MEMORY.md`, root or tier, is excluded from the listing: an index line moves with the fact it points at, so a paragraph for it would restate its neighbour and put the routing table on the same footing as the facts. Read via `gitlore_memory_approval_clause()` (`scripts/lib/util.sh`), it is appended at the end of each call site's message rather than spliced into a sentence: a template is inherently multi-line, and one line per file could not carry what a memory commit message is for — what the fact now claims and what moved it. Shipping the template rather than describing the shape is the same choice as naming the kinds: the agent copies a form instead of inferring one, and the bold prefix is what makes the body scannable in the approval blockquote. The multi-line clause also constrains emission — a hook that puts it in JSON must build that JSON with `jq --arg`, since a raw newline inside a hand-written string is invalid. The four sites keep their distinct framing (a `PostToolUse` nudge, a pending-trigger retry, a sync-guard refusal, `resolve.sh`'s divergence-path refusal) — composing a shared block into different messages, not centralizing the messages themselves, which would have erased distinctions that exist on purpose.

**Discovery mirrors D16's `gitlore.commitCommand` exactly**, because it already solved the identical problem — a caller outside gitlore's own process needing a stable path into a plugin cache whose location it cannot derive: `gitlore.memoryApprovalClauseFile` is seeded at install (`scripts/install/write-settings.sh`) and re-pinned every `SessionStart` (`scripts/cc-hooks/session-start.sh`), pointing at `$PLUGIN_ROOT/reference/memory-approval-clause.txt`. gitlore owns the wording because it already owns FR11's gate and every direct-commit call site; `handoff` is a consumer, the same relationship `commit-memory.sh` already has to it.

**No fallback copy in the consumer, and no silent skip on a missing key.** A hardcoded fallback in `handoff` was considered and rejected: the clause is only ever needed when gitlore is genuinely active, and a submodule registered without a working gitlore install already makes `handoff`'s *existing* approval instructions a dead letter (nothing consumes the IPC files they describe) — a fallback would just be one more set of instructions nothing downstream honors. The alternative to a fallback is not silence either: when the key or file can't be resolved, `handoff` reports the problem explicitly and names the fix ("gitlore plugin looks disabled — check `/plugin`") rather than skipping the whole memory-approval directive, so a broken discovery path fails loud instead of quietly dropping FR11's gate on the consumer side.

**`resolve.sh` reaches the clause through its callers, never by sourcing `util.sh` itself.** `util.sh` declares `readonly` globals, so sourcing it twice fails; `resolve.sh` leaves that to the caller and says so in its own header comment. All four scripts that source `resolve.sh` (`commit-memory.sh`, `git-hooks/pre-push`, `git-hooks/pre-commit`, `cc-hooks/session-start.sh`) source `util.sh` first, so `gitlore_memory_approval_clause` is already in scope at `resolve.sh`'s one call site — a defensive `source` line there would break every caller on a `readonly` redeclaration.

**D20 — Standalone push entry point, invoked directly by the skill rather than through a trigger file**

Memory `live` advances locally on every memory commit, but nothing reaches a remote until a parent `git push` runs `pre-push`. The standalone commit path (D16) made that gap routine rather than rare: a session can commit memory at an interactive moment and end without any parent push, leaving every fact in the local clone only. `push-memory.sh` closes it, and the split with `pre-push` is the same one `commit-memory.sh` has with `pre-commit` — the shared body in the lib, the entry-point-specific guards at each caller.

**Why the skill calls the script directly, unlike the standalone commit.** The commit path routes through an IPC file and a `PostToolBatch` hook because the auto-mode classifier refuses agent writes it reads as self-configuration, and because a denial there strands a summary the user already approved — the approval is the expensive, unrepeatable thing. Push has no approval to lose, and the classifier's objection to a submodule push does not survive an explicit `/gitlore:push`: the action *is* what the user asked for. Should a call be denied anyway, nothing has happened — no ref moved, no merge was prepared — so the recovery is one turn (re-run behind a `!` prefix) rather than a lost gate. A trigger file would buy nothing against that and would put a second IPC file, a second hook and a second stranded-trigger check in the way.

**Push is not fire-and-forget, and the skill is shaped around that.** A refused push whose reason git attributes to divergence prepares a merge and yields — which dispatches the memory-merger sub-agent, synthesizes content, and lands a merge commit under its own approval gate. So divergence is a first-class outcome in the skill body, not an error branch: resolve, then **push again**, because tiers publish before memory and resolve handles one store per pass, so a second store can still be unpublished when the first one's merge lands. That loop, not the exit code alone, is what makes "published" true.

**No approval gate of its own.** FR11 is a gate on what enters the history, applied where content is composed. Re-asking at publish time would gate a decision already made, and would train the user to approve a prompt carrying no new information — the failure mode that makes a gate ornamental. What the run *does* owe the user is an accurate report: which stores moved, how far, and — named explicitly rather than left to inference — that uncommitted changes did not go with them.

---

## Rejected Alternatives

Grouped by the part of the system they belong to. Each entry states the alternative and why it was ruled out; a decision that was later inverted lives in the changelog, not here.

### Branch model and merge

**Per-parent-branch memory branches** (the model until 2026-07-18). A memory branch named after the parent worktree's branch was only ever a local checkout handle dodging git's one-branch-per-worktree rule — detached HEADs coexist on one commit and dodge it too, and a tier *needs* that because its gitdir is shared across a repo's memory worktrees. It bought no branch-aligned history either: the commit path advances `live` immediately, so memory is repo-global the moment it is committed. Retired for the detached-at-`live` model (D17).

**`live` as a working branch, in any store or worktree.** `live` is the trunk every store fast-forwards onto and no store ever checks out as a branch. Working on it directly would make concurrent sessions compete for one ref and would re-introduce the one-checkout-per-branch collision the detached model exists to avoid.

**`git commit-tree` + `git update-ref` for the resolve merge.** Low-level plumbing to avoid checking a branch out. Unnecessary — the merge prepares with `checkout --detach <authority>`, which is ordinary porcelain, easier to reason about, and cannot collide with another worktree because nothing is ever checked out as a branch (D3, D17).

**A temporary worktree for resolve.** Indirection with no payoff; the store's own worktree is where the merge belongs.

**`claude --print` for conflict resolution.** No session context, no way to ask the user, no memory of what produced the changes.

**Single-agent resolve with a post-hoc context refresh.** The parent's in-memory picture of the files is pre-merge and stale the moment git rewrites them on disk. A sub-agent reads the post-merge state fresh (D9).

### The commit gate

**A `Stop` hook to generate the commit message.** Fires on every response turn rather than at commit intent — noise, and the wrong timing for a confirmation gate.

**`PostToolUse` on every memory `Write`/`Edit`.** Couples commit preparation to individual edits instead of to commit intent. The configured pre-commit command is a far stronger signal with cleaner timing. (D17's `PostToolBatch` composition is a different use of the same event: structural placement, no commit semantics.)

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

**A separate `gitlore.memoryPath` config key.** `.gitmodules` plus the fixed submodule name `gitlore-memory` is already canonical; a second source is a divergence risk.

**Making the memory push optional in v1.** Gitlore without shared memory is a diminished product. An opt-out can be added later as a preference.

### Memory redirect

**`autoMemoryDirectory` in `.claude/settings.json` or `.claude/settings.local.json`.** Silently ignored — CC honours the key only from `policySettings`, `flagSettings` and `userSettings`, never a project tier. Observed, not inferred: with the key written there, memory lands in the default directory and nothing reports the discard (D10).

**`autoMemoryDirectory` in global `~/.claude/settings.json`.** Honoured, but global: every project's auto-memory would redirect into one repo's submodule.

**`CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` via `.envrc`.** Highest precedence and per-project scopable, but it carries cowork semantics — it disables the native memory-write auto-allow and can inject cowork guidelines into the system prompt. `--settings` feeds the identical setting with none of that (D10).

**An explicit `gitlore` launch command instead of shadowing `claude`.** Breaks the value proposition: users would have to remember a new command. The shim keeps them typing `claude`.

### Tiered memory and index composition

**A flat merge-everything store** (one shared directory for all repos). Blows the always-loaded root-index budget and loads N irrelevant projects' facts every session. Recall is on-demand, so a large tier is free *if* it is surfaced by selection — tiered composition keeps bodies on-demand and splices only pointers into the root index (D17).

**A content classifier routing each new fact to global-vs-project.** Puts model reasoning on the write path to inspect a fact's content. Where to file a fact you are already authoring is a generation choice: the agent picks the directory, the directory is the submodule (D17).

**Frontmatter `description` as the source of truth for the index one-liner.** The two surfaces drift bidirectionally — the agent revises whichever one it has loaded, and the other rots, in both directions. Deriving the index from frontmatter would overwrite curated one-liners with stale text and degrade the *reliable* retrieval lever. The index line is canonical; frontmatter drift is healed by the one-way authoring-time sync (D17).

**An append-only constraint on shared-tier indexes.** Unnecessary. Concurrent insertions merge through the same semantic path as any memory divergence, and distinct per-index namespaces prevent cross-index collision, so conflicts resolve without constraining where the agent may insert (D17).

**A `merge` driver plus `.gitattributes` for the entry-wise index merge.** The driver has to be configured per *clone* — `memory/`, every tier, every linked worktree's tier clone — and when the pin goes stale git falls back to a text merge **silently**, which is the exact failure the entry-wise pass exists to prevent. gitlore drives every memory merge itself, so the pass has a guaranteed call site and no per-clone configuration (D17).

**`**/MEMORY.md merge=union` plus a dedup-by-path pass.** The union driver concatenates blindly and manufactures the duplicate lines the dedup then cleans — solving a problem it creates (D17).

**Propagating the root index down into the carriers during the merge continuation.** Composition there is up-only, for three independently sufficient reasons: the merged tier's facts must reach the root because that is the only surface recall reads; mirroring down writes a second store the user never reviewed as a side effect of approving one index; and it would advance `refs/gitlore/compose-base` past a reconciliation that never happened, so every line the root gained during the merge would read as a deletion next pass. In-session propagation is the hooks' job (D17).

**Recompose owning index-line presence — coverage (seed a missing pointer from frontmatter) and prune (drop a bullet whose file is gone).** Both are refused by the presence-authority rule: the index is authoritative over a line's presence, and no surface is auto-edited to match the other. Coverage resurrects a line the user deliberately removed; prune inverts the authority and destroys what may be the last trace of a lost memory. Each also hardcodes a semantic call — was this deletion deliberate? — that belongs to the agent (D17).

**Deleting a memory file when its pointer line is removed.** Prune's mirror image, refused for the same reason index authority is non-destructive: a destructive edit as the silent consequence of an index edit is the one surprise a memory store must not spring, and the file is the only place the fact still lives. Unlisting a fact and destroying it are different acts (D17).

**Scoring an index hook against its body, tf-idf style,** to flag a line with no routing value. Built and refuted on the real store: over 76 documents `df ≤ 3` marks ordinary prose words as distinctive, so the score tracks hook *length* rather than quality (means 2.06 `reference` vs 1.76 `feedback` — no separation; `reference_git_hook_env_leak` scored 0/10 with a hook carrying `GIT_*`, `unset $(git rev-parse --local-env-vars)` and `GIT_INDEX_FILE`). Document frequency needs a corpus a memory store will never have. The two countable advisories — byte budget and missing trigger token — cover what is checkable (D17).

### Active recall

**A `PreToolUse` deny on the first durable write of an episode,** forcing a recall decision before the agent may write. Making a denial the *normal* control flow spends a turn on every editing episode forever and trains the agent to read denials as routine, corroding the channel that should mean stop. Arming it at `UserPromptSubmit` is worse still: it duplicates the native classifier that already fires there. The obligation lives in the calling skill's flow instead (D18).

---

## Changelog

How the design got here is recorded in [changelog.md](changelog.md), newest first.
