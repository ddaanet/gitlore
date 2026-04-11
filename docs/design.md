# gitlore Design Document

**Status:** Living document
**Created:** 2026-04-11

---

## Functional Requirements

1. Memory files are versioned in git, inside the project repo, as a submodule
2. Memory is shared across Claude Code sessions on the same project
3. Each git worktree has its own memory branch; branches converge into a shared trunk
4. On the happy path, memory is committed transparently as part of the normal `git commit` workflow — no extra steps for the user
5. When two sessions diverge, the agent performs a semantic merge with user review before the commit proceeds
6. One-command install configures the entire system
7. Works correctly after `git clone` with no manual steps beyond install
8. Memory is pushed to a dedicated remote repository, synchronized before the parent repo push
9. Remote creation is provider-agnostic; `gh` CLI is used opportunistically when available

---

## Non-Functional Requirements

1. **No AI on the hot path.** The happy-path commit flow runs entirely in shell scripts. The agent is only invoked for conflict resolution and user interaction.
2. **Noisy failure with actionable instructions.** Hook failures exit 1 with a specific skill or command to run — never a generic error.
3. **Idempotent install.** `/gitlore:install` is safe to re-run after clone or on a new machine.
4. **Scripts decide, agent executes.** Detection logic (hook manager, remote provider, merge state) lives in shell scripts. The agent reads structured output and acts; it does not reason its way to a decision.
5. **Double-commit semantics.** Memory is committed and pushed before the parent commit/push. The parent remote always points to reachable memory.
6. **No tracked-file noise on plugin updates.** Hook scripts live in the plugin cache, not in the repo. Only stable wiring (hook manager config, sentinel file) is committed.
7. **Works with any git hook manager.** Husky, Lefthook, Overcommit, or plain `.git/hooks/`.

---

## Architecture

### Memory Submodule

Memory lives at a configurable path inside the project repo (default: `memory/`, common alternative: `.claude/memory/`). Chosen at install time. The submodule is always named `gitlore-memory` in `.gitmodules` regardless of its working-tree path:

```sh
git config --file .gitmodules submodule.gitlore-memory.path  # → memory or .claude/memory
git config gitlore.memoryPath                                  # local git config, untracked
```

### Branch Model

- **`live`** — memory trunk. Never worked on directly. All sessions merge into it.
- **Per-worktree branches** — named after the worktree directory (linked worktrees) or the current parent branch (primary worktree).
- Session start: fast-forward the worktree branch to `live`.
- After commit: ff-push the worktree branch into `live`. Block on divergence.

### Configuration

| File | Key | Value | Tracked |
|------|-----|-------|---------|
| `.claude/settings.json` | `gitlore.enabled` | `true` | Yes |
| `.claude/settings.local.json` | `autoMemoryDirectory` | `<abs-path-to-memory>` | No |
| `.git/config` | `gitlore.memoryPath` | `memory` or `.claude/memory` | No |
| `.git/config` | `gitlore.hooksDir` | abs path to plugin hooks dir | No |

**Commit message file:** `<memory-path>/.git/gitlore-commit-msg` — written by Claude alongside memory file writes, consumed and deleted by the pre-commit hook. In `.git/` so it is never tracked.

**Sentinel file:** `.claude/gitlore-hook-setup` — tracked. Contains the hook setup command (`lefthook install`, `npx husky`, or `direct`). Used by `SessionStart` to reinstall hooks on clone or new machine.

**Hook wrappers:** `SessionStart` writes two flat files to the parent repo's `.git/` on every startup:

- `.git/gitlore-pre-commit`
- `.git/gitlore-pre-push`

Each wrapper delegates to the current plugin via `git config gitlore.hooksDir`. Stable paths for hook manager configs; plugin updates are transparent.

```sh
#!/bin/sh
exec "$(git config gitlore.hooksDir)/pre-commit" "$@"
```

### Components

#### Skills

**`/gitlore:install`** — one-time setup, idempotent.

1. Prompt for memory path (default: `memory`)
2. Create memory submodule; initial commit; create `live` branch; create worktree branch from `live`
3. Write `gitlore.enabled: true` to `.claude/settings.json`
4. Write `autoMemoryDirectory` to `.claude/settings.local.json`
5. Write `gitlore.memoryPath` and `gitlore.hooksDir` to local git config
6. Migrate existing auto-memory content from `~/.claude/projects/<hash>/memory/` if present
7. Run hook manager detection script → apply config changes, write sentinel file
8. If parent has a remote: run remote detection script → present proposal to user, confirm, execute
9. Leave tracked changes staged for the user to commit

**`/gitlore:resolve`** — in-session semantic merge. Invoked after pre-commit hook failure due to divergence.

> **Skill clarity requirement:** The agent will not naturally expect the memory submodule branch to change, or that the merge runs trunk-receives-branch. The SKILL.md must explicitly orient the agent at each surprising step.

1. `BASE=$(git merge-base <branch> live)`
2. Show Claude both diffs: `git diff $BASE live` (other session), `git diff $BASE HEAD` (this session)
3. Claude reads both versions of changed files (`git show live:<file>`, `git show HEAD:<file>`), synthesizes holistically — semantic conflicts span files, not just lines
4. *"You are about to switch the memory submodule to `live`. This is intentional — live is the trunk that receives the merge. Your session's branch is the source."*
5. `git -C <memory-path> checkout live` — write lock acquired (git enforces one checkout per branch)
6. *"You are now on `live`. Merge direction is intentional: do not reverse it."*
7. `git merge --no-commit --no-ff <branch>`
8. Claude writes synthesized files; `git add -A`
9. `git commit -m "$(echo "$BRANCH_HEAD branch '<branch>'" | git fmt-merge-msg)"` → M on live (live first parent, branch second)
10. *"Advance the worktree branch pointer BEFORE switching back."*
11. `git branch -f <branch> HEAD` — advance worktree branch to M while still on live
12. *"Switching back does not change files — both `live` and `<branch>` now point to M."*
13. `git checkout <branch>`
14. Report: "Memory merged. Retry your commit."

Concurrent resolve attempt: `git checkout live` fails (already checked out) → skill reports "Another session is resolving memory. Wait and retry."

#### Claude Code Hooks

**`SessionStart`**
1. Write `autoMemoryDirectory` to `.claude/settings.local.json`
2. Set `gitlore.hooksDir` in local git config to current plugin hooks path
3. Write `.git/gitlore-pre-commit` and `.git/gitlore-pre-push` wrappers
4. If memory submodule not initialized: `git submodule update --init`; create worktree branch from `live`
5. If memory submodule worktree missing: create it; checkout worktree branch
6. Run sentinel command to reinstall hook manager wiring
7. `git merge --ff-only live` on worktree branch
8. If ff fails: emit `systemWarning` — do not proceed silently

**`WorktreeCreate`** (Claude Code-initiated worktrees only)
1. Initialize memory submodule worktree at `<worktree-path>/<memory-rel-path>`
2. Create worktree branch from `live`
3. Checkout worktree branch in the new memory worktree

`SessionStart` handles manually-created worktrees as fallback.

**`WorktreeRemove`** (advisory — cannot block)

Input provides `worktree_path` and `worktree_branch`.

1. `git worktree remove <memory-submodule-worktree-path>`
2. `git branch -D <worktree_branch>` on memory repo
3. If parent worktree branch is merged into `main`/`live`: `git branch -D <worktree_branch>` on parent repo. If unmerged: leave it.

Unmerged memory from a removed worktree is discarded — memory is auxiliary.

**`PostToolUse`** (configurable trigger command)

Fires after project pre-commit command exits 0, if memory is dirty AND `gitlore-commit-msg` is absent or older than the newest memory file.

Action: notify Claude to write or refresh `<memory>/.git/gitlore-commit-msg`.

#### Git Hooks

**`pre-commit`**

Guard: `[ -d "$(git config gitlore.memoryPath)/.git" ] || exit 0`

1. Memory clean AND branch ancestor of `live` → exit 0
2. Memory dirty, message file absent or stale → exit 1: *"Write memory commit message in your Claude Code session, then retry."*
3. Memory dirty, message file fresh → commit memory; delete message file
4. `git push . <branch>:live` (ff-only)
5. Push fails → exit 1: *"Memory diverged. Run /gitlore:resolve in your Claude Code session, then retry."*

**`pre-push`**

Guard: `[ -d "$(git config gitlore.memoryPath)/.git" ] || exit 0`

Push memory: `git -C <memory-path> push origin live`

### Hook Manager Support

Detection script outputs structured results:

| Detected | Wiring | Sentinel command |
|----------|--------|-----------------|
| Husky | Append `.git/gitlore-pre-commit` call to `.husky/pre-commit`, same for pre-push | `npx husky` |
| Lefthook | Add `gitlore` commands pointing to `.git/gitlore-pre-commit` in `lefthook.yml` | `lefthook install` |
| Overcommit | Add plugin entry in `.overcommit.yml` | `overcommit --install` |
| None | Call `.git/gitlore-pre-commit` from `.git/hooks/pre-commit` | `direct` |
| Unknown | Output snippet for manual wiring | `manual` |

### Workflows

**Commit (happy path)**
1. Claude writes memory files and `<memory>/.git/gitlore-commit-msg` in the same action
2. User runs `git commit`
3. PostToolUse hook fires if message file is absent or stale
4. pre-commit: commits memory, ff-pushes branch → `live`
5. Parent commit records updated submodule pointer
6. pre-push: pushes `live` to memory remote

**Clone**

`git clone --recurse-submodules <repo>` → first `SessionStart` configures settings, creates worktree branch, installs hooks via sentinel.

Without `--recurse-submodules`: `SessionStart` detects uninitialized submodule, runs `git submodule update --init`, proceeds as above.

**Worktree creation (manual)**

`git worktree add` → next `SessionStart` in that worktree detects missing memory submodule worktree and initializes it.

### Remote Repository

- Name: `<repo-name>-memory` (derived from parent remote)
- Created on install with explicit user confirmation
- Detection script selects method: `gh repo create` (GitHub + `gh` CLI) or manual URL + instructions
- Pushed before parent on every push (double-commit semantics)

---

## Design Decisions

**D1 — `live` branch as trunk, not `main`**
Using the primary worktree's `main` as the shared trunk would mean the primary worktree competes with other sessions on the same branch. `live` is a dedicated trunk that no session works on directly, making the merge target unambiguous. Git's one-checkout-per-branch constraint on `live` provides a natural write lock during resolve.

**D2 — Per-worktree branches, not detached HEAD**
Detached HEAD was considered for simplicity (no branch cleanup). Rejected because merge commits from a detached HEAD have no meaningful message — git cannot generate "Merge branch 'feat-x' into live" without a named source branch. Branch names are recoverable from git log; anonymous detached-HEAD merges are not.

**D3 — Checkout `live` during resolve, not git plumbing**
`git commit-tree` + `git update-ref` were designed to avoid checking out `live` in a linked worktree. Rejected in favour of a direct `git checkout live` because: (a) the linked-worktree constraint is "one checkout per branch," not "no branch switching," and `live` is never checked out during normal work; (b) the checkout approach uses standard git commands that are easier to reason about; (c) the checkout naturally acts as a write lock.

**D4 — Commit message via file handshake**
Claude writes `<memory>/.git/gitlore-commit-msg` alongside memory file writes. The pre-commit hook consumes it. Alternatives rejected:
- *Stop hook:* fires on every response turn, not just before commits — causes unnecessary writes and churn.
- *Force-write on memory edit:* PostToolUse on every Write/Edit would generate noise; freshness check on PostToolUse of pre-commit command is sufficient.
- *`claude --print`:* no session context, cannot ask user.

**D5 — Wrapper scripts in `.git/`, not tracked**
Tracking hook scripts in the repo causes a commit noise on every plugin update. Storing them in `.git/` (flat: `.git/gitlore-pre-commit`, `.git/gitlore-pre-push`) keeps them untracked and local. `SessionStart` regenerates them on every startup, always reflecting the current plugin version.

**D6 — Merge direction: branch into live**
The merge commit records "Merge branch 'feat-x' into live" with live as first parent. This preserves the conventional git ancestry reading: live's history is linear; feature branches appear as merged-in contributors. Reversing the direction would make live look like a branch of the worktree branch, which is incorrect.

**D7 — Agent executes, scripts decide**
Detection and branching logic (hook manager type, remote provider, merge state checks) lives in shell scripts that output structured results. The agent reads and acts. This ensures deterministic, testable, auditable behavior that does not vary with model version or context.

**D8 — Remote creation requires user confirmation**
Even when `gh` CLI is available, creating a remote repository is a visible external action. The agent presents the proposed action and waits for explicit approval before executing.

---

## Rejected Alternatives

| Alternative | Rejected because |
|-------------|-----------------|
| Detached HEAD for all sessions | No meaningful merge commit messages |
| `claude --print` for conflict resolution | No session context; cannot ask user; no memory of what produced the changes |
| `git commit-tree` + `git update-ref` for merge | Complex plumbing; `git checkout live` is simpler and correct |
| Temporary worktree for resolve | Unnecessary indirection; direct checkout is sufficient |
| Stop hook for commit message generation | Fires on every response turn, not just before commits |
| Tracked hook scripts in repo | Commit noise on every plugin update |
| `gh repo create` as only remote creation method | Locks out non-GitHub users; provider-agnostic push is sufficient |
| `live` as the primary worktree branch name | Confusing — `live` is the trunk, not a working branch; primary worktree should mirror parent branch name |
| Single `main` branch for all sessions | Multiple concurrent sessions on `main` compete on the same branch; no isolation |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-04-11 | Initial design |
