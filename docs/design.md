# gitlore Design Document

**Status:** Living document
**Created:** 2026-04-11

---

## Functional Requirements

1. Memory files are versioned in git, inside the project repo, as a submodule.
2. Memory is shared across Claude Code sessions on the same project.
3. Each git worktree has its own memory branch; branches converge into a shared trunk.
4. On the happy path, the agent drives memory commits: runs the configured pre-commit command, summarizes pending memory changes in prose, obtains explicit user confirmation, writes the approved summary as the memory commit message, then commits. The user's approval of the summary doubles as approval of the commit itself.
5. When any divergence is detected (local branch vs. trunk, or local trunk vs. remote), `/gitlore:resolve` performs a semantic merge. A sub-agent with fresh context synthesizes the merged content; the parent agent approves the summary with the user before the merge is committed.
6. One-command install configures the entire system.
7. After `git clone`, the first `SessionStart` restores working state automatically. Running `/gitlore:install` again is not required; the plugin's own install is the only prerequisite.
8. Memory is pushed to a dedicated remote repository with double-commit semantics — memory `live` is pushed before the parent push on every `git push`.
9. Remote creation is provider-agnostic; `gh` CLI is used opportunistically when available.
10. **Install-time disclosure (informational).** Before creating the memory remote, the user is shown the proposed name, owner, visibility, and a notice that memory may contain session context. This is orientation, not a hard gate.
11. **Per-commit review gate.** Every memory commit (including merge commits produced by `/gitlore:resolve`) requires explicit user approval of a prose summary before the commit message file is written and the commit executes. This is the effective control over what reaches the remote.
12. **Coexistence.** Repos without a `gitlore-memory` submodule are unaffected when the plugin is present. All hooks no-op silently if the submodule is not registered.
13. **Recovery.** If memory enters a broken state (missing `live`, partial merge, locked checkout), tooling surfaces a clear error with recovery instructions rather than blocking parent git operations silently.
14. **Transparent per-project redirect.** Memory is redirected into the submodule without changing how the user invokes Claude Code — they keep typing `claude`, using CC's native auto-memory. The redirect is scoped to the project (no effect on other repos' memory) and applied at launch by the Memory Redirect Launcher.

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
9. **Overrides.** Confirmation gates described here are defaults. Project or user instructions (`CLAUDE.md` and equivalents) can relax them — users who want auto-commit or auto-push can document the override.

---

## Architecture

### Memory Submodule

Memory lives at a configurable path inside the project repo (default: `memory/`, common alternative: `.claude/memory/`). Chosen at install time. The submodule is always named `gitlore-memory` in `.gitmodules` regardless of its working-tree path:

```sh
git config --file .gitmodules submodule.gitlore-memory.path   # → memory or .claude/memory
```

This is the canonical source of truth for the memory path; no duplicate local config key is maintained.

### Branch Model

- **`live`** — memory trunk. Never worked on directly. All sessions merge into it.
- **Per-worktree memory branches** — named after the corresponding parent worktree's branch.
- **Parent branch switch → memory branch switch**, always. Parent and memory branches move together.
- **Detached HEAD** on the parent → detached HEAD on memory. Branch names are a convenience; ff, commit, merge, and push all operate on detached HEAD (accepting a small readability cost — merge commits reference source by commit id instead of branch name).
- **Reserved name.** A parent branch named `live` collides with the memory trunk and is rejected at SessionStart with an error.
- **Session start:** if memory has no uncommitted changes, fast-forward the worktree branch to `live`. If uncommitted changes are present, warn the user and skip the ff.
- **ff failure at SessionStart** is an invariant violation (memory merges should happen at commit time, not session start). Emit both `systemWarning` (user-visible) and `additionalContext` (agent-visible) directing to `/gitlore:resolve`. Note that resolve at session start produces a new commit; the agent then directs the user to `/clear`.
- **After commit:** ff-push the worktree branch into `live`. Block on divergence.
- **Branch rename on parent** (`git branch -m old new`): SessionStart renames the memory branch to match. If the old name has unmerged commits or the new name exists with divergent history, that is already a pre-existing invariant violation — surface it and route to `/gitlore:resolve`. If both names exist with ff-compatible state, reconcile via ff.
- **New parent branch with stale memory branch of same name:** prompt — use a different branch name, or delete the stale memory branch.
- **Parent rebase / force-push** is independent of memory. Memory history is its own concern.
- **Stale memory branches** are cleaned up opportunistically to mirror Claude Code's handling of the parent worktree branch (determined at design time from CC documentation; fallback to testing if docs are silent). If CC retains parent branches, gitlore retains memory branches.

### Configuration

| File | Key | Value | Tracked |
|------|-----|-------|---------|
| `.claude/settings.json` | `gitlore.enabled` | `true` | Yes |
| `.claude/settings.json` | `gitlore.precommitCommand` | e.g. `lefthook run pre-commit` | Yes |
| `.git/config` | `gitlore.hooksDir` | abs path to plugin hooks dir | No |
| `.gitlore/bin/claude` | — | launcher shim (see Memory Redirect Launcher) | Yes |
| `.envrc` | `source_up_if_exists` + `PATH_add .gitlore/bin` | activates the shim inside the repo (direnv) | Yes |

> **No `autoMemoryDirectory` in project settings.** Claude Code resolves `autoMemoryDirectory` only from `policySettings`, `flagSettings` (the `--settings` flag), or `userSettings` (`~/.claude/settings.json`) — never from project-level `.claude/settings.json` or `.claude/settings.local.json`, which it discards for security. The per-project redirect is therefore injected at launch by the Memory Redirect Launcher, not written to a settings file. See D10.

**Commit message file:** resolved via `git -C <memory-path> rev-parse --git-path gitlore-commit-msg` — this handles the submodule gitdir correctly (the memory worktree's `.git` is a pointer file, not a directory). Written by Claude after user confirms the commit summary; consumed and deleted by the pre-commit hook.

**Sentinel file:** `.claude/gitlore-hook-setup` — tracked. Contains the hook setup command or keyword (`lefthook install`, `npx husky`, `overcommit --install`, `direct`, or `manual`). Used by `SessionStart` to re-wire hook-manager integration on clone or new machine.

**Hook wrappers:** `SessionStart` writes two flat files into the repo's **git common dir** on every startup, resolved via `git rev-parse --git-common-dir`:

- `<common-dir>/gitlore-pre-commit`
- `<common-dir>/gitlore-pre-push`

**Why the common dir, not `.git/` literally.** In a linked worktree, `.git` is a gitlink *file*, not a directory, so a literal `.git/gitlore-*` path fails to write *and* fails to `exec` (verified: `exec: .git/gitlore-pre-commit: not found` → commit blocked). The git **common dir** is shared across all worktrees (`git rev-parse --git-common-dir` → `.git` in the main worktree, `<main>/.git` in a linked one), so a single wrapper emitted once is reachable and executable from every worktree — including a linked worktree where no Claude session has ever run (a plain `git worktree add` followed by a `git commit`). All producers (`emit-wrappers`) and all consumers (the wired hook stubs / manager configs) resolve the wrapper through `git rev-parse --git-common-dir`; none hardcode `.git/`. This mirrors the commit-message file, which already resolves via `git rev-parse --git-path` to survive the same gitlink subtlety (see above).

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
- **Path built with `jq`.** Handles spaces/quoting safely; computed at runtime so committed shims stay portable across clones. `--settings` loads an *additional* settings tier (`flagSettings`), so only `autoMemoryDirectory` is overridden; all other settings still resolve from their normal tiers.

**Placement A — repo-local, direnv (default).** `/gitlore:install` emits two **committed** files: `.gitlore/bin/claude` (the shim) and `.envrc`. The `.envrc` must put `.gitlore/bin` at the **front** of `$PATH` so the shim shadows the real `claude` (shim before payload). direnv's `PATH_add .gitlore/bin` prepends, which is exactly this. When creating `.envrc` from scratch, `source_up_if_exists` is written as the first line so parent-directory direnv configs are inherited. Subtlety with an existing `.envrc`: direnv evaluates top-to-bottom and each `PATH_add` prepends, so the *last* `PATH_add` wins the front slot — gitlore's line must be inserted after any pre-existing `PATH_add` (idempotent no-op if already present). After a one-time `direnv allow`, the shim is on `PATH` only inside the repo tree (subdirectories included). Both files travel with the repo, so every clone gets the transparent launcher after `direnv allow`. The path is namespaced under `.gitlore/bin/` to avoid colliding with a project's own `bin/`.

**Placement B — global shim, no-direnv fallback (automatic).** When direnv is not found during install, `run.sh` automatically runs `scripts/install/global-shim.sh`, which drops the *same shim* at `~/.gitlore/bin/claude` and **prints** (does not auto-append) the one `PATH` line for the user's shell rc (e.g. `set -gx PATH ~/.gitlore/bin $PATH` for fish). Per-repo installs never touch it otherwise. Because the gitlore-repo detection is generic, this one shim auto-activates in any gitlore repo and no-ops everywhere else. This covers users without direnv and launches from outside an allowed directory.

### Components

#### Skills

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
9. Create `live` branch at the initial commit; create worktree branch (named after current parent branch, or detached HEAD if parent is detached) from `live`.
10. If a remote was created, `git -C <memory-path> push origin live` so the parent's submodule pointer is reachable upstream.
11. Write `gitlore.enabled: true` and `gitlore.precommitCommand` to `.claude/settings.json`.
12. Emit the memory redirect launcher: write `.gitlore/bin/claude` (shim) and ensure `.envrc` prepends `.gitlore/bin` to the front of `$PATH` via direnv `PATH_add .gitlore/bin` (create `.envrc` with `source_up_if_exists` on the first line, or insert the `PATH_add` line after any existing `PATH_add` so it wins the front slot; idempotent if already present). Both are staged for commit. Then activate the launcher: if direnv is available, run `direnv allow` (non-fatal — a read-only direnv dir is not a blocker); otherwise run `global-shim.sh` to install the global shim and print the `PATH` line for the user's shell rc. (Does **not** write `autoMemoryDirectory` to any settings file — that tier is ignored; see D10.)
13. Write `gitlore.hooksDir` (abs path to plugin hooks) to local git config.
14. Run hook-manager detection script → apply idempotent wiring, write sentinel file.
15. Leave tracked changes staged for the user to commit.

Idempotency rules for re-runs: existing submodule → verify and skip creation; existing settings keys → overwrite only if value differs; migration → detect prior migration (by presence of migrated files or a done-marker) and skip; existing hook-manager wiring with our marker → skip; existing remote → skip creation. A partial install (user aborted mid-flow) is recovered by re-running.

**`/gitlore:resolve`** — semantic merge on any divergence flavor. Script-driven; the agent handles language synthesis only. Self-triggering skill: when a git commit or push fails with `gitlore: memory merge prepared` on stderr, the agent invokes this skill automatically without user intervention. Standalone invocation (`/gitlore:resolve`) also supported for manual recovery.

> **Skill clarity requirement:** the agent will not naturally expect the memory submodule branch to change, or that merges run on the authoritative-trunk side. The SKILL.md must explicitly orient the agent at each surprising step.

Script entry:

1. `git -C <memory-path> fetch origin` (if a remote is configured).
2. Detect divergence flavor(s) — both can hold simultaneously and are resolved serially:
   - **Branch-vs-live:** `<branch>` not ancestor of local `live`.
   - **Local-vs-remote:** local `live` ≠ `origin/live`.
3. For each applicable flavor, run the matching plumbing sequence. All sequences dispatch a sub-agent for synthesis with an identical contract (see below).

**Branch-vs-live plumbing:**

1. `BASE=$(git merge-base <branch> live)`.
2. Orient sub-agent: "live is the trunk; your branch is the source. Merge target is live."
3. `git -C <memory-path> checkout live` — acquires the write lock via git's one-checkout-per-branch rule.
4. `git -C <memory-path> merge --no-commit --no-ff <branch>` — leaves conflict markers if any.
5. Dispatch sub-agent with context: changed files, diff3 output, base ref, source branch. Sub-agent synthesizes holistically (always, regardless of textual conflict presence — semantic conflicts can span files without any textual conflict).
6. Sub-agent writes synthesized files; `git add -A`.
7. Summary+confirm gate: sub-agent asks parent (via SendMessage) for clarification if needed; parent answers from conversation context or session logs, escalating to the user only as a last resort. Parent approves the synthesis summary with the user.
8. `git commit` (uses git-generated `MERGE_MSG`).
9. Orient: "advance the worktree branch pointer before switching back."
10. `git branch -f <branch> HEAD`.
11. `git checkout <branch>` (files don't change; both refs now point at the merge commit).

**Local-vs-remote plumbing** (`origin/live` is more authoritative than local `live`):

1. `OLD_LOCAL=$(git -C <memory-path> rev-parse live)`.
2. `git -C <memory-path> checkout live`.
3. `git -C <memory-path> reset --hard origin/live` — local `live` now points at `origin/live`.
4. `git -C <memory-path> merge --no-commit --no-ff $OLD_LOCAL`.
5. Dispatch sub-agent with context (diff3 between `origin/live` and `OLD_LOCAL`).
6. Sub-agent synthesizes, writes files, adds.
7. Summary+confirm gate (same as above).
8. `git commit` — merge commit has `origin/live` as first parent, `OLD_LOCAL` as second. Remote's linear history is preserved.
9. `git push origin live`.
10. Return to worktree branch.

**Post-resolve:**

- Mid-session: refresh parent context with the *incoming* diff (what came from live / origin). This is fine at end-of-session timing where context tends to be closing out anyway.
- Session start (recovery path): direct user to `/clear` — parent context is sparse, cheap to abandon.
- Report "Memory merged. Retry your commit/push."

**Concurrent resolve attempt:** `git checkout live` fails (already checked out elsewhere). Skill reports "Another session is resolving memory. Wait and retry." If a session crashed mid-resolve, manual recovery: `git -C <memory-path> merge --abort && git -C <memory-path> checkout <branch>` in the stuck worktree.

**Abort handling:** on re-invocation, detect `.git/.../MERGE_HEAD` on live; offer to abort the pending merge and retry cleanly.

**Sub-agent contract (identical for both flavors):**

Input: path map of changed files (side A and side B), base ref, diff3 output where applicable.
Output: synthesized file contents written to the worktree, with `git add -A` staging.
Interaction: may SendMessage the parent with clarification questions; commit only after parent approves the summary with the user.

~~**`/gitlore:install-launcher`**~~ — folded into `/gitlore:install`. `run.sh` now runs `scripts/install/global-shim.sh` automatically when direnv is not found (Placement B). No separate command needed.

#### Claude Code Hooks

**`SessionStart`**

Guards: if `gitlore.enabled` is not `true`, or `.gitmodules` has no `gitlore-memory` entry, no-op.

1. **Launcher guard.** If `GITLORE_LAUNCHED` is unset, the session was started with a plain `claude` — memory is *not* redirected and will strand in the default dir. Emit both `systemWarning` (user-visible) and `additionalContext` (agent-visible) directing the user to run `direnv allow` (Placement A) or re-run `/gitlore:install` on a machine without direnv to install the global shim (Placement B), then restart. Do **not** write `autoMemoryDirectory` to any settings file — that tier is ignored (D10).
2. Set `gitlore.hooksDir` in local git config to current plugin hooks path.
3. Write the `gitlore-pre-commit` and `gitlore-pre-push` wrappers into the git common dir (`git rev-parse --git-common-dir`). Idempotent and worktree-agnostic — in a linked worktree this targets the same shared file as the main worktree (D11).
4. If the memory submodule is not initialized: `git submodule update --init`; create worktree branch from `live` (branch named after current parent branch, or detached-HEAD mirror if parent is detached).
5. If the memory submodule worktree is missing (linked worktree scenario): create it via `git -C <main-repo>/.git/modules/gitlore-memory worktree add <worktree-path>/<memory-rel-path> <branch>`; checkout worktree branch.
6. If `live` branch is absent on the memory side (corrupt / partial install): emit clear error + `additionalContext` with recovery instructions; abort further steps.
7. Run sentinel command to reinstall hook-manager wiring (keywords `direct` and `manual` are interpreted specially — see Hook Manager Support).
8. If memory has no uncommitted changes, `git merge --ff-only live` on the worktree branch. If uncommitted changes are present, display a warning and skip.
9. If ff fails (invariant violation): emit both `systemWarning` (user-visible, prominent) and `additionalContext` (instructs agent to run `/gitlore:resolve`, and after resolve to direct the user to `/clear`).

**Worktree creation — handled by `SessionStart`, not a `WorktreeCreate` hook**

Memory-worktree setup for a new worktree happens lazily at the next `SessionStart` in that worktree (step 5 above: when the memory submodule worktree is missing, `git -C <main-repo>/.git/modules/gitlore-memory worktree add <worktree-path>/<memory-rel-path> <branch>`, then checkout the parent-named branch). This is uniform across every way a worktree comes into being:

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
2. **Branch retention is a no-op.** Verified: CC leaves the parent branch in place on worktree removal (#28422, #38287), so gitlore likewise leaves the memory branch in place; unmerged memory branches fall to the classical merged-branch sweep.
3. Gitlore never touches parent branches directly.

**`PostToolUse`** — triggers memory commit message preparation before a git commit.

Configuration: `.claude/settings.json` key `gitlore.precommitCommand` holds the project's pre-commit check command. Set at install time; required for automatic triggering. If unset, memory commit preparation relies on the user explicitly asking Claude to commit memory.

Matcher: `Bash`. The hook script inspects `tool_input.command`, compares against the configured `gitlore.precommitCommand`, and fires only on a prefix match.

Trigger conditions (all must hold):

- Matched command exited 0.
- Memory submodule worktree is dirty (uncommitted changes).
- Commit message file is absent or stale relative to memory files.

Commit message file path is always resolved via `git -C <memory-path> rev-parse --git-path gitlore-commit-msg`.

Freshness check: file mtime compared to the newest memory file's mtime. Content-hash comparison is not worth the complexity; an edit that writes identical content will re-trigger preparation, which is acceptable noise.

Action on trigger: emit `additionalContext` instructing Claude to:

1. Summarize pending memory changes in prose.
2. Present the summary to the user and await explicit confirmation.
3. On approval, write the confirmed summary to the commit message file.
4. On rejection, discuss with the user and repeat from (1).

The confirmation gate (step 2) is load-bearing — per the per-commit review gate FR, the commit message file must not exist until the user has approved the summary.

#### Git Hooks

**`pre-commit`** (runs in the parent repo's pre-commit chain)

Guard: fail-silent no-op if this repo doesn't use gitlore.

```sh
git config --file .gitmodules submodule.gitlore-memory.path >/dev/null 2>&1 || exit 0
```

Resolve memory path from `.gitmodules` and the memory branch from memory-worktree HEAD.

1. If memory is clean AND the branch HEAD equals `live` → exit 0.
2. If memory is dirty AND the commit-message file is absent or stale → exit 1 with a CLAUDECODE-branched message:
   - **`$CLAUDECODE` set:** "gitlore: memory is dirty and has no approved commit summary. Prepare a summary, present it for user confirmation, and on approval write it to `$(git -C <memory-path> rev-parse --git-path gitlore-commit-msg)`. Then retry."
   - **Unset:** "gitlore: memory has uncommitted changes with no approved commit summary. Open this project in Claude Code and ask it to commit memory, then retry."
3. If memory is dirty AND the commit-message file is fresh:
   - `git -C <memory-path> commit -F "$(git -C <memory-path> rev-parse --git-path gitlore-commit-msg)"`
   - `rm "$(git -C <memory-path> rev-parse --git-path gitlore-commit-msg)"`
4. If the branch is ahead of `live` (from step 3 or a prior un-pushed commit):
   - `git -C <memory-path> push . <branch>:live` (ff-only by default).
5. On push failure (divergence), exit 1 with a CLAUDECODE-branched message:
   - **`$CLAUDECODE` set:** "gitlore: memory branch diverged from live. Run `/gitlore:resolve` to merge, then retry the commit."
   - **Unset:** "gitlore: memory branch diverged from live. Open this project in Claude Code and run `/gitlore:resolve`, then retry."

**`pre-push`** (runs in the parent repo's pre-push chain)

Guards: no-op if this repo doesn't use gitlore, or if the memory submodule has no `origin` remote configured.

```sh
git config --file .gitmodules submodule.gitlore-memory.path >/dev/null 2>&1 || exit 0
git -C <memory-path> remote get-url origin >/dev/null 2>&1 || exit 0
```

Push memory trunk: `git -C <memory-path> push origin live`.

On failure (any cause — divergence, network, auth), exit 1 with a CLAUDECODE-branched message directing to `/gitlore:resolve`. The resolve script diagnoses the cause (fetches origin, determines flavor) and routes accordingly.

#### Memory Commit Entry Point

**`commit-memory.sh`** — a callable script (not a git hook) that commits the memory submodule and advances local `live` **without a parent commit**, so a skill can satisfy the FR11 gate at an interactive moment and a later non-interactive parent commit never trips it. See D16.

Arg-driven, `git commit`-style: `-m <summary>`, `-F <file>`, or `-F -` (stdin/heredoc). It resolves the memory path, writes the summary to the commit-msg file, then calls the shared `gitlore_sync_memory_to_live`. Guards (exit 0): not a gitlore repo / no `gitlore-memory` submodule / submodule worktree absent / memory clean-and-synced. Dirty with no summary supplied → exit 1 with a caller-facing message.

**Discovery.** A `gitlore.commitCommand` git config key resolves to `$PLUGIN_ROOT/scripts/commit-memory.sh`, re-pinned every `SessionStart` (self-healing across plugin-cache path changes, like `gitlore.hooksDir`, D5) and seeded at install in `write-settings.sh`. A caller finds the script with one `git config gitlore.commitCommand` lookup — no coupling to gitlore's internal layout.

**Shared body.** `gitlore_sync_memory_to_live` (lib) is the commit-and-advance-live logic factored out of `pre-commit`: dirty/freshness gate → `add -A` → `GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>` → `rm <msgfile>` → `push . HEAD:live` (ff) → divergence (prepare / write merge-state / emit directive / exit 1). Both `pre-commit` and `commit-memory.sh` call it — one implementation, no drift.

### Hook Manager Support

Detection script outputs structured results. Each hook manager has an idempotent wiring step (uses marker comment `# gitlore: managed` to detect and skip duplicates) and a sentinel command stored in `.claude/gitlore-hook-setup` and replayed by SessionStart on clone or plugin reinstall.

**Detection precedence** (first match wins; multiple detections produce a warning listing all found managers):

1. `.lefthook.yml` or `lefthook.yml` → Lefthook
2. `.husky/` directory → Husky (v7+)
3. `.overcommit.yml` or `.git/hooks/overcommit-hook` → Overcommit
4. Otherwise → None (direct)

The `direct` case is the default whenever no recognized manager is present — whether the repo has a hand-rolled `.git/hooks/pre-commit` (the direct installer appends, coexisting) or no hooks at all. The shared `.git/hooks` dir exists in every git repo, so direct wiring always works; defaulting bare repos to it means the double-commit guarantee (FR8) is active out of the box rather than waiting on a manual copy-paste step. `manual` is **no longer auto-detected** — it remains a valid sentinel a user can set by hand, and is still emitted for the ambiguous multi-manager case (multiple managers found → gitlore can't choose → manual instructions).

**Wiring** (applied symmetrically for pre-commit and pre-push):

| Detected | Wiring | Sentinel value |
|----------|--------|----------------|
| Lefthook | Add `gitlore` command under `pre-commit` and `pre-push` in `lefthook.yml`, with `run: '$(git rev-parse --git-common-dir)/gitlore-pre-commit'` (resp. `-pre-push`). Lefthook executes `run` via a shell, so the substitution expands at hook time. Guard-marker comment. | `lefthook install` |
| Husky | Append a guarded `exec "$(git rev-parse --git-common-dir)/gitlore-<hook>" "$@"` line to `.husky/pre-commit`; same for `.husky/pre-push`. Create files if missing. Husky runs the script via `sh`, so the substitution expands. | `npx husky` |
| Overcommit | Add a custom `gitlore` hook under `PreCommit` and `PrePush` in `.overcommit.yml`. Overcommit `command:` is an array exec'd **directly (no shell)**, so the wrapper path must be reached through an explicit shell: `command: ['sh','-c','exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"','gitlore']` (the `'gitlore'` sets `$0`; overcommit appends the applicable files as `$@`). | `overcommit --install` |
| None (direct) | Install shell stubs at `git rev-parse --git-path hooks/<hook>` (the shared common-dir hooks file) that run `exec "$(git rev-parse --git-common-dir)/gitlore-<hook>" "$@"`. Resolve the hook-file path via `--git-path` (not literal `.git/hooks/…`) so the `[ -f ]` test and `cat >` survive sentinel replay in a linked worktree. | `direct` (keyword — interpreted by SessionStart, not run as a shell command) |
| Multi / hand-set manual | Print copy-paste snippet for manual wiring; do not modify any file. Reached only when multiple managers are detected (ambiguous) or a user sets the sentinel by hand. | `manual` (keyword — SessionStart emits a user-facing reminder) |

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
7. pre-commit hook: commits memory using the commit-msg file, deletes the file, ff-pushes `<branch>` → `live`.
8. Parent commit records updated submodule pointer.

**Push (happy path)**

1. User or Claude runs `git push`. Agent-initiated push is allowed under the auto permission mode (subject to user approval of that mode).
2. pre-push hook: pushes memory `live` → memory remote `origin/live`.
3. Parent push proceeds.

**Resolve (on divergence) — primary path: agent-driven**

Most divergence is detected while the agent is attempting commit or push. The agent sees the hook's exit-1 stderr (addressed to it via the `$CLAUDECODE` branch) and invokes `/gitlore:resolve` inline without user intervention.

1. Agent invokes `/gitlore:resolve` after observing a hook failure.
2. Script fetches `origin`, detects divergence flavor(s).
3. For each flavor (branch-vs-live, then local-vs-remote), script runs matching git plumbing and dispatches a sub-agent for semantic synthesis.
4. Sub-agent reads changed files, synthesizes holistically; asks the parent via SendMessage if anything needs clarification.
5. Parent agent approves the synthesis summary with the user; sub-agent commits.
6. Script advances refs and returns to the worktree branch.
7. Parent context refreshed with incoming diff (or user directed to `/clear` if resolve ran at session start).
8. Agent retries the original commit or push.

**Resolve fallback: user-driven**

If divergence surfaces outside a Claude session (`git commit` or `git push` run from a plain terminal), the hook's stderr directs the user to open this project in Claude Code and run `/gitlore:resolve`. The primary path resumes from there.

**Clone**

`git clone --recurse-submodules <repo>` → first `SessionStart` configures settings, creates worktree branch (named after parent branch), replays hook-manager sentinel.

Without `--recurse-submodules`: `SessionStart` detects the uninitialized submodule and runs `git submodule update --init`. That leaves the memory submodule at a **detached HEAD** on the recorded gitlink SHA with only the remote-tracking `origin/live` — no local branches. Since the branch-model logic references `live` as a *local* ref (checkout source and ff-merge target), `SessionStart` first materializes a local `live` from `origin/live` (falling back to the checked-out `HEAD` when memory has no remote), then proceeds as above. Without this step the first post-clone session aborted with `fatal: 'live' is not a commit`.

**Worktree creation** — `SessionStart` in the new worktree initializes the memory submodule worktree and checks out a memory branch matching the new parent branch name. Uniform across `claude --worktree`, manual `git worktree add`, and the Desktop button (all start a session in the worktree). See "Worktree creation — handled by `SessionStart`" above for why no `WorktreeCreate` hook is used.

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

Using the parent's default branch name (`main`, `master`, `develop`, etc.) as the shared memory trunk would mean the primary worktree's memory branch competes with other sessions on the same branch. `live` is a dedicated trunk that no session works on directly, making the merge target unambiguous. Git's one-checkout-per-branch constraint on `live` provides a natural write lock during resolve.

**D2 — Per-worktree named branches by default; detached HEAD when parent is detached**

Always using detached HEAD for memory worktrees was considered (no branch cleanup). Rejected as the default: merge commits from a detached HEAD reference the source by commit id rather than branch name (e.g., "Merge commit a3f21c8" vs "Merge branch 'feat-x' into live"). Branch names give better readability in git log.

Exception: when the parent worktree is on detached HEAD, the memory worktree mirrors this state (also detached). The merge-message difference is accepted — branch names are a convenience; ff, commit, merge, and push all work on detached HEAD.

**D3 — Checkout `live` during resolve, not git plumbing**

`git commit-tree` + `git update-ref` were designed to avoid checking out `live` in a linked worktree. Rejected in favour of `git checkout live` because:

(a) Git's one-checkout-per-branch rule applies across all worktrees of a repo, but it only prohibits two simultaneous checkouts — not branch switching — and `live` is never checked out during normal work, so acquiring it is safe.
(b) Checkout uses standard git commands that are easier to reason about than low-level plumbing.
(c) The checkout naturally acts as a write lock — concurrent resolve attempts fail fast with a clear error.

**D4 — Commit message via file handshake**

Claude writes a commit message file inside the memory submodule's gitdir; the pre-commit hook reads, uses, and deletes it. Path is resolved via `git -C <memory-path> rev-parse --git-path gitlore-commit-msg` (handles the submodule gitdir correctly).

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

- **Branch-vs-live** (post-commit): local `live` is the trunk. Commit message: "Merge branch 'feat-x' into live", with `live` as first parent, `<branch>` as second.
- **Local-vs-remote** (pre-push): `origin/live` is more authoritative than local `live`. The merge commit is produced on local `live` after resetting it to `origin/live`'s tip; first parent is `origin/live`, second parent is the pre-merge local `live`.

Reversing either direction would make the authoritative side look like a branch of the divergent side, breaking the `git log --first-parent` convention.

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

Claude Code resolves `autoMemoryDirectory` only from the `policySettings`, `flagSettings`, and `userSettings` tiers (verified by reading the resolver in the CC binary, v2.1.150). Project-level `.claude/settings.json` and `.claude/settings.local.json` are deliberately excluded for security — a checked-in repo setting must not be able to redirect where a user's memory is written. The earlier design wrote `autoMemoryDirectory` to `.claude/settings.local.json`; CC silently discarded it and memory stranded in the default `~/.claude/projects/<sanitized-cwd>/memory/` dir.

The honored tiers are either global (`userSettings`, `policySettings`) or per-launch (`flagSettings`, via `--settings`). Per-project redirection without polluting other projects therefore requires supplying the value at launch. A thin `claude` shim injects `--settings '{"autoMemoryDirectory":…}'` transparently (see Memory Redirect Launcher). This keeps the value proposition intact — the user invokes Claude Code normally and uses its *native* auto-memory; only the storage directory is redirected, with no cowork semantics.

The `SessionStart` launcher guard (sentinel `GITLORE_LAUNCHED`) converts the previous silent-stranding failure into a loud, actionable warning.

**D12 — Submodule-side commit gate (defense in depth for FR11)**

FR11's per-commit review gate was enforced only on the **parent** side: the parent `pre-commit` hook reads the magic commit-message file and, finding memory clean (or no fresh summary), commits or blocks. The memory submodule is itself an ordinary git repo with no gitlore hook, so a commit made *directly inside it* — `git -C <mempath> commit`, a human `cd <mempath> && git commit`, or a script — bypassed the gate entirely: no summary, no approval, no handshake. Dogfooding on a downstream project hit exactly this (an agent recorded the submodule directly, then committed the parent over an already-clean submodule), confirming the drift the original design anticipated under "PreToolUse hook to constrain agent git ops — may revisit in v2 if drift is observed."

Two complementary mechanisms close it:

- **Hard gate (load-bearing).** A `pre-commit` hook *inside* the memory submodule, emitted by `emit-memory-gate.sh` into `git -C <mempath> rev-parse --git-path hooks/pre-commit` (the shared common hooks dir, so one emission also covers linked-worktree memory trees — D11 parity). It admits a commit **only** when the env sentinel `GITLORE_MEMORY_COMMIT=1` is present, and blocks otherwise with a `$CLAUDECODE`-branched message. Every gitlore-internal commit path exports the sentinel: the parent `pre-commit` blessed commit, both `/gitlore:resolve` merge commits, and the install initial commit. A naked commit by an agent, human, or script never sets it. This makes FR11 a shell-enforced invariant (NFR1 "no AI on hot path"; D7 "scripts decide") on *every* commit path, not just the parent route.

  An env sentinel — not "fresh magic file present" — because resolve's merge commits use git's `MERGE_MSG`, not the magic file, so a file-presence gate would block legitimate resolve commits. One sentinel covers all three blessed paths uniformly.

  The wrapper mirrors the parent wrappers (D5): it resolves the live plugin via `git config gitlore.hooksDir` and degrades to a clean `exit 0` + hint when that key is unset or stale. Because the gate fires under the *submodule's* git context — where `git config` reads the submodule config, not the parent's where SessionStart pins the key — `emit-memory-gate.sh` mirrors the parent's `gitlore.hooksDir` into the submodule config (common config, shared across submodule worktrees). The graceful-degradation window (plugin cache GC'd before the next SessionStart re-pins) admits an unguarded commit, accepted for NFR8 parity with the parent wrappers; the next SessionStart re-wires it.

- **Orientation (removes the friction of hitting the hard gate).** `SessionStart` emits a standing `additionalContext` every gitlore session stating the commit protocol: memory is a gitlore-guarded submodule; never commit inside it directly; to persist memory → summarize → get user approval → write the magic file → commit the parent. The base Claude Code memory instructions describe generic "edit files, save facts" memory with no review gate, so the agent's default is actively wrong in a gitlore repo; this corrects the model **before** the agent acts, making the hard gate a safety net rather than the everyday teacher.

This is a cleaner variant of the rejected PreToolUse alternative — a submodule hook consistent with the existing hook architecture, with none of the CC-level scoping complexity.

**D13 — Lock-contention retry wrapper for mutating memory git calls**

SessionStart, `pre-commit`, `pre-push`, and `/gitlore:resolve` all run `git -C <mempath> …` against the memory submodule. Concurrent Claude sessions (or a session racing its own background work) can collide on the index/ref lock, and a transient `index.lock` / `cannot lock ref` failure would abort the operation — blocking a commit or stranding SessionStart under `set -e`. The fix is `gitlore_git` (`scripts/lib/util.sh`), a drop-in wrapper that retries `git "$@"` on transient lock contention with exponential backoff. The default schedule (`0.1 0.2 0.4 0.8 1.6 3.2 3.7`) sums to exactly 10.0s wall-clock — the last term is the budget remainder, not a doubled value — and is overridable via `GITLORE_GIT_RETRY_SCHEDULE` (tests set it to zeros for instant runs).

Only lock-contention failures retry, recognized by `gitlore_git_is_lock_error` matching `index.lock`, `file exists`, `unable to create …*.lock`, `cannot lock ref`, and `another git process`. Every other failure fails fast — retrying a real error wastes the budget. The `is already used by worktree at` message is explicitly **not** retryable: that is D3's one-checkout-per-branch write lock signalling that another session holds the resolve lock, a deliberate fast-fail, not transient contention. The final attempt's stderr and exit code surface unchanged and stdout passes through untouched, so the wrapper is transparent to callers. Applied to mutating calls only (`branch`, `checkout`, `merge`); read-only probes never take the lock and stay on plain `git`.

**D14 — User-facing SessionStart output on `systemMessage`**

The Claude Code hook output channels were characterized (verified 2026-06-10): `systemMessage` (top-level JSON field) is the only reliably user-visible channel; `hookSpecificOutput.additionalContext` is injected into the model's context but **never echoed to the user**; stdout is consumed as JSON and not echoed; stderr is shown to the user only on exit code **2** (or any non-zero under `--verbose`). SessionStart is non-blocking — the session continues regardless of exit code.

Consequently SessionStart's two fatal notices (parent branch named `live`; memory branch diverged from `live`) used `echo "$msg" >&2; exit 1`, which surfaces to the user only under `--verbose` — effectively invisible. The "uncommitted changes, skipped ff-merge" notice had the same stderr invisibility, and the normal success path produced no user-visible confirmation at all. Routing these through the agent (`additionalContext` "tell the user…") was rejected: it puts the model on the hot path against NFR1/D7.

D14 routes every user-facing SessionStart notice through `systemMessage`, accumulated into the single SessionStart JSON the hook already writes to fd 3:

- **Branch-collision** and **divergence** errors → `systemMessage` + `exit 0` (was stderr + `exit 1`). Exit 0 because the channel is proven to work on exit 0 (the launcher guard already rides it) and unverified on exit 1, and because SessionStart's exit code is non-blocking and consumed by nothing — the error code bought nothing. The script still halts before the memory checkout/merge after a collision.
- **Dirty-skip** notice → `systemMessage` (informational; was stderr).
- **Clean success** → a brief confirmation `systemMessage` (branch synced with `live`, or detached at `live`), per the chosen always-confirm behaviour.
- **Launcher-not-redirected** warning → already on `systemMessage`; when present it leads the message and the state line follows.

`additionalContext` continues to carry the standing commit-protocol orientation (D12) on every path. The agent-vs-user text branch (`gitlore_say_for_agent_or_user`) is retained only for the git hooks (`pre-commit` / `pre-push` / `memory-pre-commit`), which run outside a session where `CLAUDECODE` may be unset; SessionStart always runs in-session, so its notices are written directly for the user.

**D15 — In-process-worktree memory-drift guard**

Claude Code's in-process `EnterWorktree` moves the session cwd into a linked worktree but **freezes the launch environment** — `PATH`, `autoMemoryDirectory`, and `CLAUDE_PROJECT_DIR` all stay pinned to the repo the session launched in (verified by transcript capture, 2026-06-09). The memory-redirect shim (D10) injects `autoMemoryDirectory` once at launch, so after an in-process `EnterWorktree` the agent edits files in the worktree while CC's auto-memory keeps writing to the **launch** repo's submodule. Memory silently strands in the wrong working copy — the cwd-vs-launch divergence is the drift signal.

A `PostToolUse` hook on the targeted matcher `EnterWorktree|ExitWorktree` (`scripts/cc-hooks/worktree-drift.sh`) catches the transition and emits one user-visible `systemMessage` (D14's substrate) when the session has drifted. The matcher was chosen after empirically confirming (2026-06-10, this repo) that `EnterWorktree` **does** fire `PostToolUse` and that a name-based matcher matches `tool_name`. That settled the prior open question against the `"*"` fast-bail alternative: a targeted matcher fires exactly once per transition — zero per-tool cost, and no de-dup state, because it cannot fire on the intervening `Bash` calls.

Drift predicate (all read-only git, bail silently on any error): the current worktree's `--show-toplevel` differs from the launch root's, **and** both resolve to one shared `--git-common-dir` (a linked worktree of the *same* repo, not an unrelated directory). `ExitWorktree` restores cwd to the launch root, so the predicate is false and the hook is silent — the Enter-warns/Exit-silent asymmetry is intentional. The guard also requires the launch repo to be a gitlore-enabled repo with a registered memory submodule; otherwise there is no redirected memory to strand. No shim change is needed — the guard reads the frozen `CLAUDE_PROJECT_DIR` (already relied on by the `version-guard` hook) and compares it to the moved cwd.

**D16 — Standalone memory-commit entry point (arg-driven)**

The only blessed path to commit memory is committing the parent repo, which fires `pre-commit` (sentinel commit + advance `live`). That is wrong for a caller that wants to commit *only* memory at an interactive moment so a later non-interactive commit never trips the FR11 gate: the parent commit drags whatever else is staged (handoff has already `git add -f`'d its task file), it doesn't stage the submodule gitlink anyway, and a naked submodule commit is blocked by the D12 gate. The motivating caller is `/commit-commands:commit`, which forbids prompting; splitting review from commit otherwise causes drift or redundant reviews. So an interactive caller (`handoff`) couples review+commit once, up front, through a standalone entry point.

The entry point is `scripts/commit-memory.sh`: it commits the dirty memory submodule with the `GITLORE_MEMORY_COMMIT=1` sentinel and advances local `live` (`push . HEAD:live`) — no parent commit. Origin push stays with `pre-push`. The commit-and-advance-live body it shares with `pre-commit` is factored into one lib function, `gitlore_sync_memory_to_live`; both callers invoke it, so the intricate divergence tail has a single implementation.

**Arg-driven, not file-driven.** The script takes the approved summary as an argument (`-m`, `-F <file>`, `-F -`), mirroring `git commit`, and writes it to the commit-msg file itself. The file reverts to what it always was — the hook↔commit IPC handshake (D4) — and stops being the caller's contract, which keeps callers from reconstructing gitlore-internal paths. The freshness gate stays *inside* the shared body because `pre-commit` still needs it to refuse un-approved commits; on the script's path it is satisfied by construction (the summary is written immediately before the commit, so the mtime check always passes). The per-commit FR11 approval therefore rests on the *caller's* contract here — the interactive caller obtains explicit user approval before invoking — while the mtime gate continues to protect the non-interactive parent path. A blessed interactive entry point trusting its caller's approval is the intended split, not a hole.

**Discovery via `gitlore.commitCommand`.** Re-pinned to `$PLUGIN_ROOT/scripts/commit-memory.sh` every `SessionStart` (the self-healing re-pin that absorbs plugin-cache path changes, exactly as `gitlore.hooksDir` does, D5) and seeded at install in `write-settings.sh`. Existing repos pick the key up on their next session — no reinstall. The key is a *path pin, not an activation signal*: a caller decides whether gitlore manages memory here from the `gitlore-memory` submodule registration in `.gitmodules` (FR12 — the same gate `pre-commit` uses, never stale), not from the presence of the key. The key only answers *where* the script is, and is trustworthy because `SessionStart` refreshed it this session; a caller should still verify the resolved path is executable and degrade with a "restart your session" hint rather than exec a missing path (the D5-extension staleness window). Graceful no-op (exit 0) mirrors the hook guards: not a gitlore repo / no `gitlore-memory` submodule / submodule worktree absent / memory clean-and-synced; dirty with no summary supplied refuses with a caller-facing message. Caller wiring is out of scope for the gitlore side: `handoff` consumes the key in its own work; `/commit-commands:commit` stays untouched until there is a second real caller.

---

## Rejected Alternatives

| Alternative | Rejected because |
|-------------|-----------------|
| Detached HEAD for all memory sessions | Merge commits reference source by commit id rather than branch name; less readable git log. Exception preserved when parent is detached (D2). |
| `claude --print` for conflict resolution | No session context; cannot ask user; no memory of what produced the changes. |
| `git commit-tree` + `git update-ref` for resolve merge | Complex plumbing; `git checkout live` is simpler and doubles as a write lock (D3). |
| Temporary worktree for resolve | Unnecessary indirection; direct checkout is sufficient. |
| Stop hook for commit-message generation | Fires on every response turn, not only before commits — noise and wrong timing for the confirmation gate. |
| PostToolUse on every memory Write/Edit | Couples commit preparation to individual edits rather than to commit intent; noisy. |
| Tracked hook scripts in repo | Commit churn on every plugin update; couples repo history to plugin versioning. |
| `gh repo create` as only remote creation method | Locks out non-GitHub users; provider-agnostic copy-paste flow is sufficient. |
| `live` as a working branch in any worktree | `live` is the trunk; working on it directly breaks the resolve write-lock invariant. Parent branches named `live` are rejected at SessionStart. |
| Single `main` branch for all memory sessions | Concurrent sessions would compete on the same branch; no isolation. |
| Push memory as optional in v1 | Gitlore without shared memory is diminished value. Optional push can be added later as a user preference. |
| Separate `gitlore.memoryPath` local config key | `.gitmodules` plus the fixed submodule name `gitlore-memory` is canonical; a duplicate source creates divergence risk. |
| Empty initial commit on install | Install uses `--allow-empty` on the initial commit as a safety net for the case where the migration source exists but is already a stub (prior failed install). The commit normally contains migrated auto-memory or a `MEMORY.md` scaffold, but the flag prevents a hard failure when it does not. |
| Unconditional memory branch deletion on WorktreeRemove | Memory branches mirror Claude Code's parent-branch policy; no special "memory is auxiliary, discard" rule. CC keeps the parent branch on removal (verified 2.1.150), so the memory branch is kept too. |
| `WorktreeCreate` hook to set up the memory worktree | It is an override hook (must create the worktree and print only its path on stdout; extra stdout hangs CC #27467), carries no branch in stdin, and misses Desktop-created worktrees. `SessionStart` in the new worktree does the setup uniformly with none of that fragility (verified CC 2.1.150). |
| In-session diff dump for commit review | Too noisy in the TUI; user inspects the diff in their own git tooling when desired, approves via prose summary. |
| Interactive prompt in pre-commit hook | Blocks non-interactive git commits (CI, scripts); agent-mediated confirmation is cleaner. |
| Single-agent resolve with post-hoc context refresh | Sub-agent with fresh context avoids acting on stale in-session assumptions. Accepted experimental-flag dependency (D9). |
| PreToolUse hook to constrain agent git ops | Load-bearing gate is the commit-msg file invariant at the hook level; PreToolUse would be belt-and-suspenders with scoping complexity. **Superseded by D12** — the predicted drift was observed (a direct submodule commit bypassed FR11), and the fix is a submodule-side `pre-commit` gate consistent with the hook architecture, not a CC-level hook. |
| `autoMemoryDirectory` in `.claude/settings.local.json` (or `.json`) | Silently ignored — CC honors `autoMemoryDirectory` only from `policySettings`/`flagSettings`/`userSettings`, never project tiers (D10). Was the original implementation; memory stranded in the default dir. |
| `autoMemoryDirectory` in global `~/.claude/settings.json` (`userSettings`) | Honored, but global — every project's auto-memory would redirect into one repo's submodule. Not per-project. |
| `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` env var via `.envrc` | Highest-precedence and per-project-scopable, but carries cowork semantics: disables the native memory-write auto-allow and can inject cowork guidelines into the system prompt. Compromises the "plain native auto-memory" value proposition; the `--settings` flag feeds the identical setting with none of that baggage (D10). |
| Explicit `gitlore` launch command instead of shadowing `claude` | Breaks the value proposition — users would have to remember a new command. Transparency (keep typing `claude`) is the goal; the shim shadows `claude` instead. |
| Literal `.git/gitlore-<hook>` wrapper path | Fails in linked worktrees (`.git` is a gitlink file): write aborts SessionStart, exec blocks the commit. Replaced by the common-dir anchor (D11). |
| Per-worktree wrapper anchor (`--git-path gitlore-<hook>`) | Reintroduces the commit-blocking gap in any worktree where no session has run, since the shared wired stub would exec a non-existent per-worktree wrapper. Common-dir anchor (D11) has no such gap. |
| Trigger memory commit via a parent commit (pointer-bump / `--allow-empty` / unstage-everything-else) | All fight the hook's parent-commit requirement and the gitlink-staging wrinkle, and drag unrelated staged files. The standalone entry point (D16) sidesteps all of it. |
| Reimplement the sentinel / `push HEAD:live` / merge-state logic in the caller (handoff) plugin | Fragile duplication of gitlore internals that would drift from `pre-commit`. The logic lives in gitlore behind `commit-memory.sh` (D16); callers resolve it via `gitlore.commitCommand`. |
| Caller pre-writes the commit-msg file; entry point only validates freshness | Couples external callers to the gitlore-internal commit-msg path and keeps two approval semantics in the system. Arg-driven (D16) keeps one IPC handshake (D4) internal and a single `git commit`-style contract for callers. |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-10 | **Implemented D15 — in-process-worktree memory-drift guard.** CC's in-process `EnterWorktree` moves cwd but freezes the launch env (`CLAUDE_PROJECT_DIR`, `autoMemoryDirectory`), so memory written in a worktree strands in the launch repo's submodule. New `PostToolUse` hook on matcher `EnterWorktree|ExitWorktree` (`scripts/cc-hooks/worktree-drift.sh`) emits one `systemMessage` when cwd toplevel ≠ launch root with a shared git common-dir (gitlore-enabled launch repo only); `ExitWorktree` is silent by predicate. Matcher choice settled by empirically confirming `EnterWorktree` fires `PostToolUse` and name-matches (2026-06-10) — targeted beats `"*"` (once per transition, no de-dup). Wired in `hooks/hooks.json`; tests `cc_hook_worktree_drift.bats` (5) + a distribution wiring guard. |
| 2026-06-10 | **Implemented D14 — user-facing SessionStart output on `systemMessage`.** Every user-visible SessionStart notice now rides the single SessionStart `systemMessage` (the only reliably user-visible hook channel — verified 2026-06-10; stderr surfaces only on exit 2 / `--verbose`). The two fatal notices (parent branch named `live`; memory diverged from `live`) changed from `echo >&2; exit 1` (effectively invisible) to `systemMessage` + `exit 0` (non-blocking; exit code consumed by nothing). The dirty-skip notice moved off stderr, and a clean start now emits a brief confirmation (`memory ready (… synced with live)`), per the always-confirm choice. `session-start.sh` gains a `sysmsg` accumulator + `emit_session_json` helper; `gitlore_say_for_agent_or_user` is retained only for the git hooks (which run outside a session). `additionalContext` still carries the D12 commit-protocol orientation on every path. `cc_hook_session_start.bats`: 3 tests rewritten + 1 added (divergence); 183 green. |
| 2026-06-10 | **Documented D13 — lock-contention retry wrapper (`gitlore_git`).** Shipped in `27042ce`: `scripts/lib/util.sh` gains `gitlore_git` (retry mutating `git` on transient lock contention, 10s exponential backoff, `GITLORE_GIT_RETRY_SCHEDULE`-overridable) and `gitlore_git_is_lock_error` (matches `index.lock`/`cannot lock ref`/… but fast-fails D3's `is already used by worktree at` write-lock). Threaded through SessionStart, `pre-commit`, `pre-push`, `resolve.sh`, and the install scripts on mutating calls only. Tests: `lib_util.bats` (+lock-classifier and retry cases). |
| 2026-06-09 | **Implemented D12 — submodule-side commit gate closes the FR11 bypass.** A direct `git -C <mempath> commit` (agent, human, or script) bypassed the per-commit review gate, which lived only on the parent `pre-commit`; found dogfooding on a downstream project. Fix, two parts: (A, load-bearing) a new `scripts/git-hooks/memory-pre-commit` gate, emitted by `scripts/emit-memory-gate.sh` into the submodule's common hooks dir (`--git-path hooks/pre-commit`), that blocks any commit lacking the `GITLORE_MEMORY_COMMIT=1` env sentinel — now exported by all three blessed paths (parent `pre-commit:66`, both `resolve.sh` merge commits, install `init-submodule.sh`). The wrapper degrades on unset/stale `gitlore.hooksDir` like the parent wrappers (D5); since it fires in the submodule git context, `emit-memory-gate.sh` mirrors the parent's `gitlore.hooksDir` into the submodule config. (B) `SessionStart` emits a standing commit-protocol `additionalContext` every session, correcting the generic-memory mental model before the agent acts. Updated the "PreToolUse hook" Rejected Alternative to "superseded by D12". New tests: `git_hook_memory_pre_commit.bats` (3), `emit_memory_gate.bats` (9), `integration_memory_gate.bats` (2), plus SessionStart gate-wiring + standing-context cases. 180 green. |
| 2026-05-31 | **Wrapper degrades on a stale (GC'd) hooks dir, not just an unset one (D5 extension).** `gitlore.hooksDir` is version-pinned and only re-pinned at SessionStart; in the window between a plugin upgrade (old cache GC'd) and the next session, a plain-terminal `git commit`/`push` made the wrapper `exec` a missing path and hard-fail. Wrappers now also skip-with-hint when `$HOOKS_DIR/<hook>` is not executable. Surfaced in the 0.2.1 install bug report (finding #7). Part of an install-rough-edges sweep also covering: scripts self-locating `CLAUDE_PLUGIN_ROOT` (#1), sandbox-write probing with paste-able fallback (#2), remote creation brought back into FR9/FR10/D8 compliance — opportunistic `gh` with parent-matched visibility, copy-paste-URL for other providers, first-class local-only, confirmation gate, and `<parent-remote-name>-memory` naming from the parent origin instead of the local dir basename (#5/#6), and a stray-blank-line fix in `.gitignore` (#9). |
| 2026-05-29 | **Hook detection defaults to `direct`, not `manual`.** `detect.sh` previously emitted `direct` only when an executable, untracked `.git/hooks/pre-commit` already existed; a repo with no recognized manager and no pre-existing hook (the common case) fell through to `manual`, which only prints a snippet and modifies nothing — so the pre-push double-commit hook silently never fired until hand-wired. Surfaced by dogfooding: gitlore's own repo (gitmoji installed only `commit-msg`) sat on `manual`, so `just release`'s `git push` never pushed the memory submodule. Detection now defaults the no-manager case to `direct` (wire-direct installs `.git/hooks/{pre-commit,pre-push}` stubs — always available, coexists with a hand-rolled hook by appending). `manual` is no longer auto-detected; it stays a hand-set sentinel and the multi-manager fallback. The release recipe (`plugin-dev/release.just`) is intentionally left untouched — it is generic, vendored tooling shared across plugins and must not know about gitlore's memory submodule; the git pre-push hook is the correct layer. This repo wired via `wire-direct.sh`. Detection tests updated; 153 green. |
| 2026-05-27 | **`source_up_if_exists` added to fresh `.envrc`.** When `emit-launcher.sh` creates `.envrc` from scratch, it now writes `source_up_if_exists` as the first line so parent-directory direnv configs are inherited. Existing `.envrc` files are not modified. |
| 2026-05-27 | **Prep for 0.2.0 release.** `direnv allow` in `run.sh` made non-fatal (`|| true`) — a read-only direnv allow-dir (e.g. sandbox) no longer aborts install. `2>/dev/null` suppressions removed from diagnostic-paths in `resolve.sh`, `lib/resolve.sh`, and `create-remote.sh`; retained only where errors are genuinely expected (missing config keys, detection probes, cross-platform fallbacks). `install` step 12 description updated to reflect automatic launcher activation (was "Remind the user to run `direnv allow`"). README updated — launcher activation paragraph now describes the automated behavior instead of instructing the user to run `direnv allow` manually. |
| 2026-05-26 | **Fixed FR7 clone-restore bug.** Added a clone-from-remote integration test (`tests/integration_clone_restore.bats`): build an origin via the real install flow (gh-mock + local bare → memory remote carries `live`), clone without `--recurse-submodules`, run only `SessionStart`. It exposed a real defect — `git submodule update --init` leaves a detached HEAD with only `origin/live`, so `SessionStart`'s `checkout -b <branch> live` died with `fatal: 'live' is not a commit`; every fresh clone failed to restore. Fix: `SessionStart` materializes a local `live` (from `origin/live`, else `HEAD`) after submodule init, before the branch-model logic. 136 tests green. |
| 2026-05-25 | **Implemented D11.** All five hook managers (direct, husky, lefthook, overcommit, manual) and `emit-wrappers` now anchor the wrapper at `$(git rev-parse --git-common-dir)/gitlore-<hook>`; direct wiring resolves the hook file via `--git-path hooks/<hook>`. `pre-commit`/`pre-push` early-exit in session-less worktrees (`[ -e "$mempath/.git" ]`). SessionStart lazily creates the memory submodule worktree; new advisory `WorktreeRemove` hook removes it (registered matcher-less — the event has no matcher support). Overcommit's `sh -c` array `$@`-forwarding verified by test. |
| 2026-04-11 | Initial design |
| 2026-05-25 | **Plan 06 rethink → D11 (gitlink-aware wrappers).** Executing Plan 06 surfaced that the wrapper indirection hardcoded `.git/gitlore-<hook>`, which only resolves in the main worktree. Verified empirically (git 2.47.3): in a linked worktree the write aborts SessionStart and the shared wired hook's `exec` blocks the commit. Plan 06's memory-worktree-creation premise was therefore necessary but not sufficient — linked worktrees were unusable at a more basic level. Resolution (D11): anchor wrappers at `$(git rev-parse --git-common-dir)/gitlore-<hook>` on both write and exec sides, across all five hook managers; add an early `[ -e "$mempath/.git" ] || exit 0` guard in `pre-commit`/`pre-push` for session-less worktrees. Plan 06's two deliverables (SessionStart memory-worktree creation; advisory `WorktreeRemove`) are absorbed into the superseding plan. Corrected the "SessionStart covers linked worktrees" claim to note the D11 prerequisite. |
| 2026-05-25 | Plan 06 design: verified worktree-hook I/O against CC 2.1.150. `WorktreeCreate` is an override hook (fires pre-creation, must emit only the worktree path on stdout, no branch in stdin) — **not used**; memory-worktree setup happens at `SessionStart` in the new worktree instead (covers `claude --worktree`, manual `git worktree add`, and the Desktop button uniformly). `WorktreeRemove` (advisory, `worktree_path`-only) removes the memory submodule worktree; branch retention confirmed a no-op (CC keeps the parent branch on removal). Corrected the prior wrong assumption that command hooks receive `worktree_path`/`worktree_branch` on stdin. |
| 2026-05-25 | Released `0.1.1` (patch). Migrated 6 stranded pre-launcher memories into the submodule; pushed `main` (launcher) + the `gitlore-memory` submodule to GitHub. Bumped `plugin.json`/`marketplace.json` `0.1.0`→`0.1.1` so `/plugin update` re-fetches the launcher (same version string keeps the stale cache — see `plugin-cache-staleness` lesson). |
| 2026-05-24 | Plan 05 built the Memory Redirect Launcher (shim + Placement A direnv + Placement B global + SessionStart guard) and removed the dead `settings.local.json` `autoMemoryDirectory` writes from `write-settings.sh`/`session-start.sh` (the tier CC ignores — D10). |
| 2026-05-26 | **Commands made script-driven (D7 / 12-factor-agents).** `install.md` collapsed to 2 steps — gather inputs, run `run.sh` once. Direnv/global-shim dispatch moved into `run.sh` (if direnv found: `direnv allow`; else: `global-shim.sh`). `/gitlore:install-launcher` command removed; its behavior is now automatic. `resolve.md` converted to a self-triggering skill: description updated with `gitlore: memory merge prepared` trigger pattern; commit-triggered entry mode added (skips initial script run — directive already in context from the hook); `Resume commit` step added to retry the original commit after resolve succeeds. |
| 2026-05-23 | Memory redirect reworked. Discovered CC honors `autoMemoryDirectory` only from `policySettings`/`flagSettings`/`userSettings` — the prior `.claude/settings.local.json` write was silently ignored and memory stranded in the default dir. Added the Memory Redirect Launcher: a transparent `claude` shim injecting `--settings` (one shim, two placements — repo-local committed `.gitlore/bin/claude` + `.envrc` `PATH_add` via direnv as default; global `~/.gitlore/bin/claude` via `global-shim.sh` / Placement B as no-direnv fallback). Added `GITLORE_LAUNCHED` sentinel (anti-double-inject + SessionStart launcher guard). Install no longer writes `autoMemoryDirectory`; SessionStart warns loudly when launched without the shim. Added D10 and four Rejected Alternatives (project-tier setting, global userSettings, cowork env override, explicit launch command). |
| 2026-04-23 | Full design review. Added FRs for install-time disclosure, per-commit review gate, coexistence, and recovery. Added NFRs for graceful degradation and overrides. Removed `gitlore.memoryPath` in favour of `.gitmodules` as canonical path source. Corrected commit-message file path to use `git rev-parse --git-path`. Rewrote Branch Model to specify parent-branch-name rule, detached-HEAD mirror, rename handling, and collision with reserved `live`. Agent-driven commit flow replaces user-driven. `/gitlore:resolve` now covers both branch-vs-live and local-vs-remote divergence, with sub-agent synthesis under `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Added D9 for the sub-agent decision. Install is git-atomic (non-empty initial commit). Hook wrappers gracefully degrade when `gitlore.hooksDir` is unset. Hook stderr branches on `$CLAUDECODE` for agent vs user targeting. Remote creation inherits parent visibility. Expanded Rejected Alternatives with new entries discovered during review. |
