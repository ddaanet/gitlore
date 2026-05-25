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
| `.envrc` | `PATH_add .gitlore/bin` | activates the shim inside the repo (direnv) | Yes |

> **No `autoMemoryDirectory` in project settings.** Claude Code resolves `autoMemoryDirectory` only from `policySettings`, `flagSettings` (the `--settings` flag), or `userSettings` (`~/.claude/settings.json`) — never from project-level `.claude/settings.json` or `.claude/settings.local.json`, which it discards for security. The per-project redirect is therefore injected at launch by the Memory Redirect Launcher, not written to a settings file. See D10.

**Commit message file:** resolved via `git -C <memory-path> rev-parse --git-path gitlore-commit-msg` — this handles the submodule gitdir correctly (the memory worktree's `.git` is a pointer file, not a directory). Written by Claude after user confirms the commit summary; consumed and deleted by the pre-commit hook.

**Sentinel file:** `.claude/gitlore-hook-setup` — tracked. Contains the hook setup command or keyword (`lefthook install`, `npx husky`, `overcommit --install`, `direct`, or `manual`). Used by `SessionStart` to re-wire hook-manager integration on clone or new machine.

**Hook wrappers:** `SessionStart` writes two flat files to the parent repo's `.git/` on every startup:

- `.git/gitlore-pre-commit`
- `.git/gitlore-pre-push`

Each wrapper delegates to the current plugin via `git config gitlore.hooksDir`. Stable paths for hook manager configs; plugin updates are transparent. If `gitlore.hooksDir` is unset (a plain `git commit` outside any Claude session before SessionStart has fired), the wrapper exits 0 after emitting a stderr hint — `"gitlore skipped: hooks not installed"` plus instructions to install the marketplace, plugin, and start Claude.

```sh
#!/bin/sh
HOOKS_DIR=$(git config gitlore.hooksDir 2>/dev/null)
if [ -z "$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
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

**Placement A — repo-local, direnv (default).** `/gitlore:install` emits two **committed** files: `.gitlore/bin/claude` (the shim) and `.envrc`. The `.envrc` must put `.gitlore/bin` at the **front** of `$PATH` so the shim shadows the real `claude` (shim before payload). direnv's `PATH_add .gitlore/bin` prepends, which is exactly this. Subtlety with an existing `.envrc`: direnv evaluates top-to-bottom and each `PATH_add` prepends, so the *last* `PATH_add` wins the front slot — gitlore's line must be inserted after any pre-existing `PATH_add` (idempotent no-op if already present). After a one-time `direnv allow`, the shim is on `PATH` only inside the repo tree (subdirectories included). Both files travel with the repo, so every clone gets the transparent launcher after `direnv allow`. The path is namespaced under `.gitlore/bin/` to avoid colliding with a project's own `bin/`.

**Placement B — global shim, no-direnv fallback (opt-in).** A one-time, machine-level step — `scripts/install/global-shim.sh`, surfaced as `/gitlore:install-launcher` — drops the *same shim* at `~/.gitlore/bin/claude` and **prints** (does not auto-append) the one `PATH` line for the user's shell rc (e.g. `set -gx PATH ~/.gitlore/bin $PATH` for fish). Per-repo installs never touch it. Because the gitlore-repo detection is generic, this one shim auto-activates in any gitlore repo and no-ops everywhere else. This covers users without direnv and launches from outside an allowed directory.

### Components

#### Skills

**`/gitlore:install`** — one-time setup, idempotent.

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
12. Emit the memory redirect launcher: write `.gitlore/bin/claude` (shim) and ensure `.envrc` prepends `.gitlore/bin` to the front of `$PATH` via direnv `PATH_add .gitlore/bin` (create `.envrc`, or insert the line after any existing `PATH_add` so it wins the front slot; idempotent if already present). Both are staged for commit. Remind the user to run `direnv allow`. (Does **not** write `autoMemoryDirectory` to any settings file — that tier is ignored; see D10.)
13. Write `gitlore.hooksDir` (abs path to plugin hooks) to local git config.
14. Run hook-manager detection script → apply idempotent wiring, write sentinel file.
15. Leave tracked changes staged for the user to commit.

Idempotency rules for re-runs: existing submodule → verify and skip creation; existing settings keys → overwrite only if value differs; migration → detect prior migration (by presence of migrated files or a done-marker) and skip; existing hook-manager wiring with our marker → skip; existing remote → skip creation. A partial install (user aborted mid-flow) is recovered by re-running.

**`/gitlore:resolve`** — semantic merge on any divergence flavor. Script-driven; the agent handles language synthesis only.

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

**`/gitlore:install-launcher`** — one-time, machine-level setup for the global launcher fallback (Placement B). Runs `scripts/install/global-shim.sh`, which writes `~/.gitlore/bin/claude` (the same shim as the repo-local one) and prints the `PATH` line for the user's shell rc. Idempotent. Not invoked by `/gitlore:install`; offered to users without direnv. The shell rc is printed, never auto-edited.

#### Claude Code Hooks

**`SessionStart`**

Guards: if `gitlore.enabled` is not `true`, or `.gitmodules` has no `gitlore-memory` entry, no-op.

1. **Launcher guard.** If `GITLORE_LAUNCHED` is unset, the session was started with a plain `claude` — memory is *not* redirected and will strand in the default dir. Emit both `systemWarning` (user-visible) and `additionalContext` (agent-visible) directing the user to run `direnv allow` (Placement A) or install the launcher via `/gitlore:install-launcher` (Placement B), then restart. Do **not** write `autoMemoryDirectory` to any settings file — that tier is ignored (D10).
2. Set `gitlore.hooksDir` in local git config to current plugin hooks path.
3. Write `.git/gitlore-pre-commit` and `.git/gitlore-pre-push` wrappers.
4. If the memory submodule is not initialized: `git submodule update --init`; create worktree branch from `live` (branch named after current parent branch, or detached-HEAD mirror if parent is detached).
5. If the memory submodule worktree is missing (linked worktree scenario): create it via `git -C <main-repo>/.git/modules/gitlore-memory worktree add <worktree-path>/<memory-rel-path> <branch>`; checkout worktree branch.
6. If `live` branch is absent on the memory side (corrupt / partial install): emit clear error + `additionalContext` with recovery instructions; abort further steps.
7. Run sentinel command to reinstall hook-manager wiring (keywords `direct` and `manual` are interpreted specially — see Hook Manager Support).
8. If memory has no uncommitted changes, `git merge --ff-only live` on the worktree branch. If uncommitted changes are present, display a warning and skip.
9. If ff fails (invariant violation): emit both `systemWarning` (user-visible, prominent) and `additionalContext` (instructs agent to run `/gitlore:resolve`, and after resolve to direct the user to `/clear`).

**`WorktreeCreate`** (Claude Code-initiated worktrees only)

Guard: no-op if `.gitmodules` has no `gitlore-memory` entry.

1. `git -C <main-repo>/.git/modules/gitlore-memory worktree add <worktree-path>/<memory-rel-path> <branch>` — initializes the memory submodule worktree at the correct gitdir.
2. `<branch>` is the hook's `worktree_branch` input (the new parent worktree's branch name). Per Branch Model rules: if the memory branch already exists and is ff-compatible with `live`, ff and use; if diverged, prompt user.
3. Checkout the worktree branch in the new memory worktree.

Manually-created worktrees (`git worktree add` outside Claude Code) fall back to `SessionStart`.

> **Hook I/O note (for the worktree-hooks plan).** `WorktreeCreate`/`WorktreeRemove` are wired as **command** hooks, so they consume `worktree_path` / `worktree_branch` from the hook **input** (stdin JSON) — as steps above already do. The `hookSpecificOutput.worktreePath` *output* field reported by the CC hooks docs is **HTTP-hooks-only** and is not available to command hooks, so do not plan to emit it. Per `claude-code-guide` 2026-05-24; verify the input field names against the live binary before implementing.

**`WorktreeRemove`** (advisory — cannot block)

Input provides `worktree_path` and `worktree_branch`.

Guard: no-op if `.gitmodules` has no `gitlore-memory` entry.

1. `git -C <memory-gitdir> worktree remove <memory-submodule-worktree-path>`. On failure (locked, uncommitted changes), emit a warning; do not block parent worktree removal.
2. Apply Claude Code's branch-retention policy (the same rule it applies to the parent branch) to the memory branch. Determined at design time from CC documentation (fallback to testing if docs are silent). If CC does not delete parent branches on worktree removal — current assumption pending verification — this step is a no-op and unmerged memory branches fall to the classical merged-branch sweep.
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

### Hook Manager Support

Detection script outputs structured results. Each hook manager has an idempotent wiring step (uses marker comment `# gitlore: managed` to detect and skip duplicates) and a sentinel command stored in `.claude/gitlore-hook-setup` and replayed by SessionStart on clone or plugin reinstall.

**Detection precedence** (first match wins; multiple detections produce a warning listing all found managers):

1. `.lefthook.yml` or `lefthook.yml` → Lefthook
2. `.husky/` directory → Husky (v7+)
3. `.overcommit.yml` or `.git/hooks/overcommit-hook` → Overcommit
4. Executable `.git/hooks/pre-commit` not tracked by any manager → None (direct)
5. Otherwise → Unknown

**Wiring** (applied symmetrically for pre-commit and pre-push):

| Detected | Wiring | Sentinel value |
|----------|--------|----------------|
| Lefthook | Add `gitlore` command under `pre-commit` and `pre-push` in `lefthook.yml`, pointing at `.git/gitlore-pre-commit` and `.git/gitlore-pre-push`. Guard-marker comment. | `lefthook install` |
| Husky | Append guarded line (`exec` the wrapper) to `.husky/pre-commit`; same for `.husky/pre-push`. Create files if missing. | `npx husky` |
| Overcommit | Add custom hook under `PreCommit` and `PrePush` in `.overcommit.yml`, pointing at the wrappers. | `overcommit --install` |
| None (direct) | Install shell stubs at `.git/hooks/pre-commit` and `.git/hooks/pre-push` that `exec` the `.git/gitlore-*` wrappers. | `direct` (keyword — interpreted by SessionStart, not run as a shell command) |
| Unknown | Print copy-paste snippet for manual wiring; do not modify any file. | `manual` (keyword — SessionStart emits a user-facing reminder) |

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

Without `--recurse-submodules`: `SessionStart` detects uninitialized submodule, runs `git submodule update --init`, proceeds as above.

**Worktree creation**

- **Claude Code-initiated:** `WorktreeCreate` hook initializes memory submodule worktree and checks out a memory branch matching the new parent branch name.
- **Manual (`git worktree add`):** next `SessionStart` in that worktree handles setup as fallback.

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

**D5 — Wrapper scripts in `.git/`, not tracked**

Tracking hook scripts in the repo would cause commit churn on every plugin update and couple the repo's history to the plugin's versioning. Storing flat wrappers in `.git/` (`.git/gitlore-pre-commit`, `.git/gitlore-pre-push`) keeps them untracked and local. `SessionStart` regenerates them on every startup, so they always reflect the current plugin version.

Wrappers exec the real hook scripts via `$(git config gitlore.hooksDir)/<hook>`. If `gitlore.hooksDir` is unset, the wrappers exit 0 after emitting a stderr hint directing the user to install the marketplace, plugin, and start Claude. Keeps git operations unblocked in non-gitlore contexts.

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
| Empty initial commit on install | Install is git-atomic when the initial commit contains migrated auto-memory or a `MEMORY.md` scaffold. |
| Unconditional memory branch deletion on WorktreeRemove | Memory branches mirror Claude Code's parent-branch policy; no special "memory is auxiliary, discard" rule. |
| In-session diff dump for commit review | Too noisy in the TUI; user inspects the diff in their own git tooling when desired, approves via prose summary. |
| Interactive prompt in pre-commit hook | Blocks non-interactive git commits (CI, scripts); agent-mediated confirmation is cleaner. |
| Single-agent resolve with post-hoc context refresh | Sub-agent with fresh context avoids acting on stale in-session assumptions. Accepted experimental-flag dependency (D9). |
| PreToolUse hook to constrain agent git ops | Load-bearing gate is the commit-msg file invariant at the hook level; PreToolUse would be belt-and-suspenders with scoping complexity. May revisit in v2 if drift is observed. |
| `autoMemoryDirectory` in `.claude/settings.local.json` (or `.json`) | Silently ignored — CC honors `autoMemoryDirectory` only from `policySettings`/`flagSettings`/`userSettings`, never project tiers (D10). Was the original implementation; memory stranded in the default dir. |
| `autoMemoryDirectory` in global `~/.claude/settings.json` (`userSettings`) | Honored, but global — every project's auto-memory would redirect into one repo's submodule. Not per-project. |
| `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` env var via `.envrc` | Highest-precedence and per-project-scopable, but carries cowork semantics: disables the native memory-write auto-allow and can inject cowork guidelines into the system prompt. Compromises the "plain native auto-memory" value proposition; the `--settings` flag feeds the identical setting with none of that baggage (D10). |
| Explicit `gitlore` launch command instead of shadowing `claude` | Breaks the value proposition — users would have to remember a new command. Transparency (keep typing `claude`) is the goal; the shim shadows `claude` instead. |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-04-11 | Initial design |
| 2026-05-24 | Plan 05 built the Memory Redirect Launcher (shim + Placement A direnv + Placement B global + SessionStart guard) and removed the dead `settings.local.json` `autoMemoryDirectory` writes from `write-settings.sh`/`session-start.sh` (the tier CC ignores — D10). |
| 2026-05-23 | Memory redirect reworked. Discovered CC honors `autoMemoryDirectory` only from `policySettings`/`flagSettings`/`userSettings` — the prior `.claude/settings.local.json` write was silently ignored and memory stranded in the default dir. Added the Memory Redirect Launcher: a transparent `claude` shim injecting `--settings` (one shim, two placements — repo-local committed `.gitlore/bin/claude` + `.envrc` `PATH_add` via direnv as default; global `~/.gitlore/bin/claude` via `/gitlore:install-launcher` as no-direnv fallback). Added `GITLORE_LAUNCHED` sentinel (anti-double-inject + SessionStart launcher guard). Install no longer writes `autoMemoryDirectory`; SessionStart warns loudly when launched without the shim. Added D10 and four Rejected Alternatives (project-tier setting, global userSettings, cowork env override, explicit launch command). |
| 2026-04-23 | Full design review. Added FRs for install-time disclosure, per-commit review gate, coexistence, and recovery. Added NFRs for graceful degradation and overrides. Removed `gitlore.memoryPath` in favour of `.gitmodules` as canonical path source. Corrected commit-message file path to use `git rev-parse --git-path`. Rewrote Branch Model to specify parent-branch-name rule, detached-HEAD mirror, rename handling, and collision with reserved `live`. Agent-driven commit flow replaces user-driven. `/gitlore:resolve` now covers both branch-vs-live and local-vs-remote divergence, with sub-agent synthesis under `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Added D9 for the sub-agent decision. Install is git-atomic (non-empty initial commit). Hook wrappers gracefully degrade when `gitlore.hooksDir` is unset. Hook stderr branches on `$CLAUDECODE` for agent vs user targeting. Remote creation inherits parent visibility. Expanded Rejected Alternatives with new entries discovered during review. |
